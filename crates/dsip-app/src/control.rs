//! The control socket: the running app, reachable by the same user on the same machine through a Unix socket in a
//! directory only they can open. One JSON [`Command`] per line in, one [`Response`] per line out; after a
//! `subscribe`, one [`Change`](crate::Change) per line until the client goes. `dsip-app run` serves it; `dsip-app
//! call …` and the others are its clients.
//!
//! Impl: Unix only for now (Linux, macOS); Windows gets a named pipe admitting only its user, as Anvil's does, with
//! the desktop app (stage A3).

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

use crate::{App, Command, Response};

/// This user's default socket: `$XDG_RUNTIME_DIR/dsip-app/control.sock`, else the cache directory's.
pub fn default_path() -> PathBuf {
    let base = dirs::runtime_dir().or_else(dirs::cache_dir).unwrap_or_else(std::env::temp_dir);
    base.join("dsip-app").join("control.sock")
}

/// Serve `app` on `path` until the app stops. The directory is made only the user's (0700); a socket left by an app
/// that is gone is replaced, one that answers is not.
pub async fn serve(app: App, path: &Path) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))?;
    }
    if path.exists() {
        if UnixStream::connect(path).await.is_ok() {
            return Err(std::io::Error::new(std::io::ErrorKind::AddrInUse, format!("an app already serves {}", path.display())));
        }
        std::fs::remove_file(path)?;
    }
    let listener = UnixListener::bind(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    tracing::info!("control socket {}", path.display());
    loop {
        tokio::select! {
            accepted = listener.accept() => {
                let (stream, _) = accepted?;
                let app = app.clone();
                tokio::spawn(async move {
                    if let Err(e) = client(app, stream).await {
                        tracing::debug!("control client: {e}");
                    }
                });
            }
            _ = app.stopped() => break,
        }
    }
    let _ = std::fs::remove_file(path);
    Ok(())
}

async fn client(app: App, stream: UnixStream) -> std::io::Result<()> {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }
        let cmd: Command = match serde_json::from_str(&line) {
            Ok(c) => c,
            Err(e) => {
                write_line(&mut write, &Response::error(format!("not a command: {e}"))).await?;
                continue;
            }
        };
        if cmd == Command::Subscribe {
            let mut changes = app.subscribe();
            write_line(&mut write, &Response::State { state: Box::new(app.state()) }).await?;
            loop {
                match changes.recv().await {
                    Ok(c) => write_line(&mut write, &c).await?,
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                        // too far behind: start it again from the state
                        write_line(&mut write, &Response::State { state: Box::new(app.state()) }).await?
                    }
                    Err(_) => return Ok(()),
                }
            }
        }
        let response = app.command(cmd).await;
        write_line(&mut write, &response).await?;
    }
    Ok(())
}

async fn write_line(w: &mut (impl AsyncWriteExt + Unpin), v: &impl serde::Serialize) -> std::io::Result<()> {
    let mut line = serde_json::to_vec(v).map_err(std::io::Error::other)?;
    line.push(b'\n');
    w.write_all(&line).await
}

/// Send `cmd` to the app serving `path`; its response.
pub async fn request(path: &Path, cmd: &Command) -> std::io::Result<Response> {
    let mut stream = UnixStream::connect(path).await?;
    write_line(&mut stream, cmd).await?;
    let mut lines = BufReader::new(stream).lines();
    let line = lines.next_line().await?.ok_or_else(|| std::io::Error::other("the app closed the socket"))?;
    serde_json::from_str(&line).map_err(std::io::Error::other)
}

/// Subscribe to the app serving `path`: each line it sends (the state, then one change per line) goes to `each`
/// until the app stops or `each` returns false.
pub async fn watch(path: &Path, mut each: impl FnMut(&str) -> bool) -> std::io::Result<()> {
    let mut stream = UnixStream::connect(path).await?;
    write_line(&mut stream, &Command::Subscribe).await?;
    let mut lines = BufReader::new(stream).lines();
    while let Some(line) = lines.next_line().await? {
        if !each(&line) {
            break;
        }
    }
    Ok(())
}
