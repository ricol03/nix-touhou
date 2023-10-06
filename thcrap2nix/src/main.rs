mod bindings;
mod thcrap;
mod thcrapdef;
mod utils;
use clap::arg;
use clap::command;
use clap::Parser;

use std::collections::BTreeMap;
use std::collections::BTreeSet;

use std::env::set_var;

#[macro_use]
extern crate log;
use crate::bindings::get_status_t_GET_CANCELLED;
use crate::bindings::get_status_t_GET_CLIENT_ERROR;
use crate::bindings::get_status_t_GET_CRC32_ERROR;
use crate::bindings::get_status_t_GET_DOWNLOADING;
use crate::bindings::get_status_t_GET_OK;
use crate::bindings::get_status_t_GET_SERVER_ERROR;
use crate::bindings::get_status_t_GET_SYSTEM_ERROR;
use crate::thcrap::PatchDesc;
use crate::thcrap::THCrapDLL;
use crate::thcrap::THRepo;
use crate::thcrapdef::THCrapDef;
use crate::utils::str_from_pi8_nul_utf8;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[arg()]
    json: String,
}

fn main() {
    let args = Cli::parse();
    set_var("RUST_LOG", "trace");
    set_var("http_proxy", "http://192.168.76.1:30086");
    set_var("https_proxy", "http://192.168.76.1:30086");
    pretty_env_logger::init();
    info!("thcrap2nix");
    trace!("{:?}", std::env::current_dir().unwrap());
    info!("json path = {}", args.json);
    let file = std::fs::read_to_string(&args.json).unwrap();
    let def: THCrapDef = serde_json::de::from_str(&file).unwrap();
    trace!("json = {:?}", &def);
    //set_var("CURLOPT_CAINFO", std::env::var("HOST_SSL_CERT_FILE").unwrap());
    let thcrap = THCrapDLL::new();
    info!("Fetching thcrap repositories.");
    let repo_list = thcrap
        .RepoDiscover_wrapper("https://mirrors.thpatch.net/nmlgc/")
        .unwrap();
    info!("Repo Len = {}", repo_list.len());
    let mut search_tree: BTreeMap<String, (&THRepo<'_>, BTreeMap<String, PatchDesc<'_>>)> =
        BTreeMap::new();
    for repo in repo_list.iter() {
        let mut repo_search_tree = BTreeMap::new();
        let id = repo.id().to_owned();
        let patches = repo.patches();
        info!("Repo = {}", id);
        for p in patches {
            info!("  {} {}", p.1.patch_id(), p.0);
            let pid = p.1.patch_id();
            repo_search_tree.insert(pid.to_owned(), p.1);
        }
        search_tree.insert(id, (repo, repo_search_tree));
    }
    info!("Collecting patches.");
    let mut has_error = false;
    let mut installed: BTreeSet<(String, String)> = BTreeSet::new();
    let mut remaining = vec![];
    for patch in def.patches.iter() {
        if let Some((_repo, tree)) = search_tree.get(&patch.repo_id) {
            if let Some(desc) = tree.get(&patch.patch_id) {
                remaining.push(*desc);
            } else {
                error!("Missing patch: {}/{}", &patch.repo_id, &patch.patch_id);
                has_error = true;
            }
        } else {
            error!("Missing repo id: {}", &patch.repo_id);
            has_error = true;
        }
    }
    if has_error {
        error!("Some specified patches are missing.");
        std::process::exit(1);
    }
    let mut has_error = false;
    while let Some(patch_desc) = remaining.pop() {
        let key = (
            patch_desc.repo_id().unwrap().to_owned(),
            patch_desc.patch_id().to_owned(),
        );
        if !installed.contains(&key) {
            info!("Installing patch: {}/{}", &key.0, &key.1);
            let (repo, current_repo_tree) = search_tree.get(&key.0).unwrap();
            let mut patch = patch_desc.load_patch(repo);
            for mut dep in patch.dependencies() {
                // First try to resolve relative.
                if !dep.absolute() {
                    trace!(
                        "Resolving relative dependency: {} relative to {}",
                        dep.patch_id(),
                        &key.0
                    );
                    let did = dep.patch_id();
                    if current_repo_tree.contains_key(did) {
                        trace!("Relative dependency resolved by current repo.");
                        dep.patchdesc.repo_id = patch_desc.patchdesc.repo_id;
                    } else {
                        trace!("Relative dependency resolving by all repos.");
                        for repo in search_tree.iter() {
                            if repo.1 .1.contains_key(did) {
                                trace!("Relative dependency resolved by repo: {}", repo.0);
                                unsafe { dep.patchdesc.repo_id = (*repo.1 .0.repo).id };
                                break;
                            }
                        }
                    }
                }
                if dep.absolute() {
                    if let Some((repo, tree)) = search_tree.get(dep.repo_id().unwrap()) {
                        if let Some(desc) = tree.get(dep.patch_id()) {
                            remaining.push(*desc);
                        } else {
                            error!(
                                "Missing patch dependency: {}/{}",
                                &dep.repo_id().unwrap(),
                                &dep.patch_id()
                            );
                            has_error = true;
                        }
                    } else {
                        error!("Missing repo id: {}", &dep.repo_id().unwrap());
                        has_error = true;
                    }
                } else {
                    error!("Unresolved relative dependency: {}!", dep.patch_id());
                    has_error = true;
                }
            }
            patch.add_to_stack();
            installed.insert(key);
        } else {
            debug!("Dependency already resolved: {}/{}", &key.0, &key.1);
        }
    }
    if has_error {
        error!("Failure detected during patch dependency resolution.");
        std::process::exit(2);
    }
    trace!("Downloading game patches.");
    let has_error = std::sync::atomic::AtomicBool::new(false);
    thcrap.stack_update_wrapper(
        |name| {
            //trace!("Filter processing {}", name);
            return !name.contains('/');
        },
        |progress| unsafe {
            let prog = &*progress;
            let patch = str_from_pi8_nul_utf8((*prog.patch).id).unwrap();
            let file = str_from_pi8_nul_utf8(prog.fn_).unwrap();
            match prog.status {
                get_status_t_GET_DOWNLOADING => {
                    let url = str_from_pi8_nul_utf8(prog.url).unwrap();
                    trace!(
                        "{} {} {}/{} Downloading from URL {}",
                        patch,
                        prog.file_progress,
                        prog.file_size,
                        file,
                        url
                    );
                }
                get_status_t_GET_OK => {
                    trace!("{} {} Downloaded", patch, file);
                }
                get_status_t_GET_CLIENT_ERROR => {
                    let error = str_from_pi8_nul_utf8(prog.error).unwrap();
                    error!("{} {} Client error {}", patch, file, error);
                    has_error.store(true, std::sync::atomic::Ordering::Relaxed);
                }
                get_status_t_GET_SERVER_ERROR => {
                    let error = str_from_pi8_nul_utf8(prog.error).unwrap();
                    error!("{} {} Server error {}", patch, file, error);
                    has_error.store(true, std::sync::atomic::Ordering::Relaxed);
                }
                get_status_t_GET_SYSTEM_ERROR => {
                    let error = str_from_pi8_nul_utf8(prog.error).unwrap();
                    error!("{} {} System error {}", patch, file, error);
                    has_error.store(true, std::sync::atomic::Ordering::Relaxed);
                }
                get_status_t_GET_CRC32_ERROR => {
                    error!("{} {} CRC32 error", patch, file);
                    has_error.store(true, std::sync::atomic::Ordering::Relaxed);
                }
                get_status_t_GET_CANCELLED => {
                    trace!("{} {} Cancelled", patch, file);
                }
                _ => {}
            }
        },
    );
    if has_error.load(std::sync::atomic::Ordering::Relaxed) {
        error!("Failure detected while downloading.");
        std::process::exit(3);
    }

    info!("thcrap update finished.")
    //thcrap.
}

#[no_mangle]
pub extern "C" fn _Unwind_Resume(_ex_obj: *mut ()) {
    // _ex_obj is actually *mut uw::_Unwind_Exception, but it is private
}
