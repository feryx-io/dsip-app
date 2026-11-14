//! A video call's pictures on Flutter textures, as Anvil's app shows them.
//!
//! Pictures never cross into Dart. The runner's texture plugin (Windows: `windows/runner/video_texture.cpp`;
//! Android: `VideoTextures.kt` with `src/android_video.rs`) makes a texture and hands Dart its id with a C function
//! and its argument; Dart hands those here ([`attach_tile`]), and the video host's threads call the function with
//! each picture, as RGBA, when it is to be seen. Where the app has no video (Linux, macOS, iOS for now) nothing is
//! attached.

/// Show a tile on a texture: call `stream`'s picture (the app's call id), or (`None`) this side's camera. `present`
/// is the texture plugin's `void present(void* texture, const uint8_t* rgba, uint32_t width, uint32_t height)` and
/// `texture` its argument; it is called on the video host's threads, never after [`detach_tile`] returns. The
/// attachment's id.
#[flutter_rust_bridge::frb(sync)]
pub fn attach_tile(stream: Option<u32>, present: usize, texture: usize) -> anyhow::Result<u64> {
    native::attach(stream, present, texture)
}

/// What a tile shows: its picture's size, and whether it is frozen (broken until a keyframe).
pub struct TileInfo {
    /// Pixels across.
    pub width: u32,
    /// Pixels down.
    pub height: u32,
    /// Frozen until the next keyframe.
    pub frozen: bool,
}

/// A tile's picture, once it has one.
#[flutter_rust_bridge::frb(sync)]
pub fn tile_info(stream: Option<u32>) -> Option<TileInfo> {
    native::info(stream)
}

/// Stop showing an attachment; its function is not called again.
#[flutter_rust_bridge::frb(sync)]
pub fn detach_tile(attachment: u64) {
    native::detach(attachment);
}

#[cfg(not(any(target_os = "android", windows)))]
mod native {
    use super::TileInfo;

    pub(super) fn attach(_stream: Option<u32>, _present: usize, _texture: usize) -> anyhow::Result<u64> {
        anyhow::bail!("this app has no video here")
    }

    pub(super) fn info(_stream: Option<u32>) -> Option<TileInfo> {
        None
    }

    pub(super) fn detach(_attachment: u64) {}
}

#[cfg(any(target_os = "android", windows))]
mod native {
    use std::collections::HashMap;
    use std::ffi::c_void;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Arc;

    use anvil_video::{Picture, Renderer, TileKey, Tiles};
    use parking_lot::Mutex;

    use super::TileInfo;

    type Present = unsafe extern "C" fn(*mut c_void, *const u8, u32, u32);

    /// The running app's tiles.
    fn tiles() -> anyhow::Result<Tiles> {
        crate::api::app::current()
            .and_then(|app| app.video_tiles())
            .ok_or_else(|| anyhow::anyhow!("no video: the app is not running, or has none"))
    }

    /// A texture a tile is shown on. `buffer` is `None` once detached: the lock held while presenting is what makes
    /// "never after detach" so.
    struct Texture {
        present: Present,
        texture: usize,
        buffer: Mutex<Option<Vec<u8>>>,
    }

    impl Renderer for Texture {
        fn present(&self, picture: &Picture) {
            let mut buffer = self.buffer.lock();
            let Some(rgba) = buffer.as_mut() else { return };
            picture.write_rgba(rgba);
            // SAFETY: the plugin's function with the texture it gave for it, called only until it is detached (the
            // plugin disposes of the texture after Dart detaches), with a buffer of width × height × 4 bytes that
            // outlives the call.
            unsafe { (self.present)(self.texture as *mut c_void, rgba.as_ptr(), picture.width, picture.height) };
        }
    }

    /// Each attachment by id: the tile and the texture it shows on.
    type Attached = HashMap<u64, (TileKey, Arc<Texture>)>;
    static ATTACHED: Mutex<Option<Attached>> = Mutex::new(None);
    static NEXT: AtomicU64 = AtomicU64::new(1);

    fn key(stream: Option<u32>) -> TileKey {
        match stream {
            Some(s) => TileKey::Stream(anvil_core::video::host::StreamId(s)),
            None => TileKey::SelfView,
        }
    }

    pub(super) fn attach(stream: Option<u32>, present: usize, texture: usize) -> anyhow::Result<u64> {
        anyhow::ensure!(present != 0 && texture != 0, "no texture");
        let tiles = tiles()?;
        // SAFETY: Dart passes the address of the plugin's `present`, of the type documented on `attach_tile`.
        let present: Present = unsafe { std::mem::transmute::<usize, Present>(present) };
        let key = key(stream);
        let renderer = Arc::new(Texture { present, texture, buffer: Mutex::new(Some(Vec::new())) });
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        ATTACHED.lock().get_or_insert_with(HashMap::new).insert(id, (key, Arc::clone(&renderer)));
        tiles.attach(key, renderer);
        Ok(id)
    }

    pub(super) fn info(stream: Option<u32>) -> Option<TileInfo> {
        let stats = tiles().ok()?.stats(key(stream))?;
        (stats.presented > 0).then_some(TileInfo { width: stats.width, height: stats.height, frozen: stats.frozen })
    }

    pub(super) fn detach(attachment: u64) {
        let mut attached = ATTACHED.lock();
        let Some(map) = attached.as_mut() else { return };
        let Some((key, texture)) = map.remove(&attachment) else { return };
        // not called again, from here on
        *texture.buffer.lock() = None;
        // the tile is let go unless a newer attachment shows it
        if !map.values().any(|(k, _)| *k == key) {
            if let Ok(tiles) = tiles() {
                tiles.detach(key);
            }
        }
    }
}
