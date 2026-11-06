// Worktree metadata resolution adapted from nanvon/cc-bar (MIT).
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
use std::{
    fs,
    path::{Path, PathBuf},
};

pub(crate) fn main_project_path(path: &str) -> Option<String> {
    let path = Path::new(path);
    if !path.is_absolute() {
        return None;
    }
    let mut directory = fs::canonicalize(path).ok()?;
    if !directory.is_dir() {
        return None;
    }
    loop {
        fs::read_dir(&directory).ok()?;
        let dot_git = directory.join(".git");
        if dot_git.exists() {
            let git = if dot_git.is_dir() {
                fs::canonicalize(&dot_git).ok()?
            } else {
                let marker = read_small_text(&dot_git)?;
                let relative = marker.strip_prefix("gitdir:")?.trim();
                if relative.is_empty() {
                    return None;
                }
                resolve(relative, &directory)?
            };
            fs::File::open(git.join("HEAD")).ok()?;
            let common_file = git.join("commondir");
            if common_file.exists() {
                let common_path = read_small_text(&common_file)?;
                if common_path.is_empty() {
                    return None;
                }
                let common = resolve(&common_path, &git)?;
                if common.file_name()? != ".git" || !common.join("objects").is_dir() {
                    return None;
                }
                fs::File::open(common.join("HEAD")).ok()?;
                return Some(display_path(common.parent()?));
            }
            return git
                .join("objects")
                .is_dir()
                .then(|| display_path(&directory));
        }
        directory = directory.parent()?.to_path_buf();
    }
}

fn resolve(path: &str, directory: &Path) -> Option<PathBuf> {
    fs::canonicalize(directory.join(path)).ok()
}

fn read_small_text(path: &Path) -> Option<String> {
    let metadata = fs::metadata(path).ok()?;
    if !metadata.is_file() || metadata.len() > 4096 {
        return None;
    }
    Some(fs::read_to_string(path).ok()?.trim().to_owned())
}

fn display_path(path: &Path) -> String {
    let text = path.to_string_lossy();
    #[cfg(windows)]
    {
        if let Some(unc) = text.strip_prefix(r"\\?\UNC\") {
            return format!(r"\\{unc}");
        }
        if let Some(drive) = text.strip_prefix(r"\\?\") {
            return drive.into();
        }
    }
    text.into_owned()
}
