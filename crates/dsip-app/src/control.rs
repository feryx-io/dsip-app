//! The control channel: the running app, reachable by the same user on the same machine. On Linux and macOS it is a
//! Unix socket in a directory only they can open; on Windows, a named pipe only they can open, whose server a client
//! checks runs as them (`user_only.rs`), as Anvil's. One JSON [`Command`] per line in, one
//! [`Response`] per line out; after a `subscribe`, one [`Change`](crate::Change) per line until the client goes.
//! `dsip-app run` serves it; `dsip-app call …` and the others are its clients.

use std::path::{Path, PathBuf};

use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};

use crate::{App, Command, Response};

/// This user's default: `$XDG_RUNTIME_DIR/dsip-app/control.sock` (else the cache directory's) on Linux and macOS,
/// `\\.\pipe\dsip-app-<user>` on Windows.
pub fn default_path() -> PathBuf {
    if cfg!(windows) {
        let user = std::env::var("USERNAME").unwrap_or_else(|_| "user".into());
        return PathBuf::from(format!(r"\\.\pipe\dsip-app-{user}"));
    }
    let base = dirs::runtime_dir().or_else(dirs::cache_dir).unwrap_or_else(std::env::temp_dir);
    base.join("dsip-app").join("control.sock")
}

/// Serve `app` on `path` until the app stops: a Unix socket, or on Windows the pipe `path` names (`\\.\pipe\…`). A
/// socket's directory is made only the user's (0700); a socket left by an app that is gone is replaced, one that
/// answers is not, nor a pipe someone already serves.
pub async fn serve(app: App, path: &Path) -> std::io::Result<()> {
    platform::serve(app, path).await
}

/// One client: commands answered until it goes; after `subscribe`, the state, then every change.
async fn client(app: App, stream: impl AsyncRead + AsyncWrite + Unpin) -> std::io::Result<()> {
    let (read, mut write) = tokio::io::split(stream);
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
    w.write_all(&line).await?;
    w.flush().await
}

/// Send `cmd` to the app serving `path`; its response.
pub async fn request(path: &Path, cmd: &Command) -> std::io::Result<Response> {
    let mut stream = platform::connect(path).await?;
    write_line(&mut stream, cmd).await?;
    let mut lines = BufReader::new(stream).lines();
    let line = lines.next_line().await?.ok_or_else(|| std::io::Error::other("the app closed the connection"))?;
    serde_json::from_str(&line).map_err(std::io::Error::other)
}

/// Subscribe to the app serving `path`: each line it sends (the state, then one change per line) goes to `each`
/// until the app stops or `each` returns false.
pub async fn watch(path: &Path, mut each: impl FnMut(&str) -> bool) -> std::io::Result<()> {
    let mut stream = platform::connect(path).await?;
    write_line(&mut stream, &Command::Subscribe).await?;
    let mut lines = BufReader::new(stream).lines();
    while let Some(line) = lines.next_line().await? {
        if !each(&line) {
            break;
        }
    }
    Ok(())
}

#[cfg(unix)]
mod platform {
    use std::os::unix::fs::PermissionsExt;
    use std::path::Path;

    use tokio::net::{UnixListener, UnixStream};

    use crate::App;

    pub(super) async fn serve(app: App, path: &Path) -> std::io::Result<()> {
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
                        if let Err(e) = super::client(app, stream).await {
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

    pub(super) async fn connect(path: &Path) -> std::io::Result<UnixStream> {
        UnixStream::connect(path).await
    }
}

#[cfg(windows)]
mod platform {
    use std::path::Path;
    use std::time::Duration;

    use tokio::net::windows::named_pipe::{ClientOptions, NamedPipeClient};

    use crate::user_only::{served_by_this_user, UserOnly};
    use crate::App;

    fn name(path: &Path) -> std::io::Result<&str> {
        path.to_str()
            .filter(|n| n.starts_with(r"\\.\pipe\"))
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidInput, format!("{}: not a pipe name (\\\\.\\pipe\\…)", path.display())))
    }

    pub(super) async fn serve(app: App, path: &Path) -> std::io::Result<()> {
        let name = name(path)?;
        let mut access = UserOnly::new()?;
        let mut server = match access.create(name, true) {
            Ok(server) => server,
            // the name is taken: our own app, or someone else posing as it
            Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
                let why = match connect(path).await {
                    Ok(_) => "an app already serves",
                    Err(_) => "someone else serves",
                };
                return Err(std::io::Error::new(std::io::ErrorKind::AddrInUse, format!("{why} {name}")));
            }
            Err(e) => return Err(e),
        };
        tracing::info!("control pipe {name}");
        loop {
            tokio::select! {
                connected = server.connect() => {
                    connected?;
                    // the next instance before this one is handed on, so a client finds one to open
                    let stream = std::mem::replace(&mut server, access.create(name, false)?);
                    let app = app.clone();
                    tokio::spawn(async move {
                        if let Err(e) = super::client(app, stream).await {
                            tracing::debug!("control client: {e}");
                        }
                    });
                }
                _ = app.stopped() => break,
            }
        }
        Ok(())
    }

    /// Open the pipe, waiting while every instance is busy (the server makes its next instance only after a client
    /// connected), and only if this user serves it: commands and their answers go only to our own app.
    pub(super) async fn connect(path: &Path) -> std::io::Result<NamedPipeClient> {
        const ERROR_PIPE_BUSY: i32 = 231;
        let name = name(path)?;
        let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
        let pipe = loop {
            match ClientOptions::new().open(name) {
                Err(e) if e.raw_os_error() == Some(ERROR_PIPE_BUSY) && tokio::time::Instant::now() < deadline => {
                    tokio::time::sleep(Duration::from_millis(20)).await;
                }
                other => break other?,
            }
        };
        if !served_by_this_user(&pipe)? {
            return Err(std::io::Error::new(std::io::ErrorKind::PermissionDenied, format!("{name} is served by another user")));
        }
        Ok(pipe)
    }
}
