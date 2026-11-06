fn main() {
    println!("cargo:rerun-if-env-changed=TAURI_UPDATER_PUBLIC_KEY");
    println!("cargo:rerun-if-env-changed=CODEX_QUOTA_RELEASE_NOTES_FILE");
    let notes = match std::env::var_os("CODEX_QUOTA_RELEASE_NOTES_FILE").filter(|path| !path.is_empty()) {
        Some(path) => {
            let path = std::path::PathBuf::from(path);
            println!("cargo:rerun-if-changed={}", path.display());
            std::fs::read_to_string(path).expect("无法读取本版本更新说明")
        }
        None => String::new(),
    };
    let destination = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap())
        .join("installed-release-notes.md");
    std::fs::write(destination, notes).expect("无法嵌入本版本更新说明");
    tauri_build::build();
}
