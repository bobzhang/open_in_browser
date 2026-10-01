///|
/// What `open` did with a URL.
pub(all) enum Outcome {
  /// A browser opener was started; the browser takes it from there. The opener
  /// is not waited on, so this does not prove a window appeared.
  Launched
  /// Deliberately not attempted, and why: `"over SSH"` (the browser would open
  /// on the remote machine) or `"without a display"` (a Linux session with no
  /// graphical display). Pass `force=true` to try anyway.
  Skipped(String)
  /// No opener could be started; the last error.
  Failed(String)
} derive(Eq, Debug)

///|
/// The commands that would open `url` in the default browser on `platform`,
/// in the order to try them, or why not to try at all.
///
/// - `$BROWSER`, when set, wins: a list of commands separated by `:` (`;` on
///   Windows), tried in order. `%s` in a command is replaced by the URL;
///   otherwise the URL is appended as the last argument.
/// - Over SSH (`SSH_CONNECTION` or `SSH_TTY` set) nothing is tried, since the
///   browser would open on the remote machine; `force=true` overrides this.
/// - macOS: `open <url>`. On Linux `open` can be a different program
///   (`openvt`), so it is never used there.
/// - Windows: `rundll32 url.dll,FileProtocolHandler <url>`, which takes the URL
///   as one argument with no shell in between, so `?`, `&` and `#` are safe.
/// - Linux under WSL: `wslview <url>`, then `explorer.exe <url>`, both of which
///   open the Windows browser.
/// - Other Linux: `xdg-open <url>` when there is a display (`DISPLAY` or
///   `WAYLAND_DISPLAY`); without one nothing is tried unless `force=true`.
///
/// Blank environment values count as unset. This function only decides; it
/// starts nothing, which makes it easy to test or to show to a user.
pub fn commands(
  platform : @types.Platform,
  url : String,
  env~ : Map[String, String],
  force? : Bool = false,
) -> Result[Array[Array[String]], String] {
  let set = (name : String) => env.get(name) is Some(value) && !value.is_blank()
  if env.get("BROWSER") is Some(browser) && !browser.is_blank() {
    let separator = match platform {
      Windows => ";"
      _ => ":"
    }
    let candidates = []
    for entry in browser.split(separator) {
      let words = entry
        .split(" ")
        .filter(word => !word.is_empty())
        .map(word => word.to_owned())
        .to_array()
      if words.is_empty() {
        continue
      }
      if words.any(word => word.contains("%s")) {
        candidates.push(words.map(word => word.replace_all(old="%s", new=url)))
      } else {
        candidates.push([..words, url])
      }
    }
    if !candidates.is_empty() {
      return Ok(candidates)
    }
  }
  if !force && (set("SSH_CONNECTION") || set("SSH_TTY")) {
    return Err("over SSH")
  }
  match platform {
    MacOS => Ok([["open", url]])
    Windows => Ok([["rundll32", "url.dll,FileProtocolHandler", url]])
    Linux =>
      if set("WSL_DISTRO_NAME") || set("WSL_INTEROP") {
        Ok([["wslview", url], ["explorer.exe", url]])
      } else if force || set("DISPLAY") || set("WAYLAND_DISPLAY") {
        Ok([["xdg-open", url]])
      } else {
        Err("without a display")
      }
  }
}

///|
/// Open `url` in the default browser, best effort, without blocking.
///
/// The commands from `commands` are tried in order until one starts. Each is
/// started detached and never waited on (some `xdg-open` setups run the
/// browser itself in the foreground), with its output sent to the null device
/// so nothing lands on a terminal the caller may own, such as a TUI. A missing
/// command moves on to the next; the result says what happened.
///
/// `env` defaults to the process environment; pass one to decide from another.
///
/// ```moonbit nocheck
/// match @open_in_browser.open("http://127.0.0.1:8080/") {
///   Launched => println("opened it in your browser")
///   Skipped(why) => println("not opening a browser \{why}")
///   Failed(error) => println("could not open a browser: \{error}")
/// }
/// ```
pub async fn open(
  url : String,
  force? : Bool = false,
  env? : Map[String, String],
) -> Outcome {
  let env = match env {
    Some(env) => env
    None => @env.get_env_vars()
  }
  match commands(@async.platform, url, env~, force~) {
    Err(reason) => Skipped(reason)
    Ok(candidates) => {
      let mut last = "no command to run"
      for command in candidates {
        match launch(command) {
          Ok(_) => return Launched
          Err(error) => last = error
        }
      }
      Failed(last)
    }
  }
}

///|
/// Start `command` detached with its output discarded.
async fn launch(command : Array[String]) -> Result[Unit, String] {
  let null_device = match @async.platform {
    Windows => "NUL"
    _ => "/dev/null"
  }
  try {
    let sink = @process.redirect_to_file(null_device)
    let _ = @process.spawn_orphan(
      command[0],
      command[1:],
      stdout=sink,
      stderr=sink,
    )
    Ok(())
  } catch {
    @os_error.OSError(_) as error if error.is_ENOENT() =>
      Err("`\{command[0]}` not found")
    error => Err("\{error}")
  }
}
