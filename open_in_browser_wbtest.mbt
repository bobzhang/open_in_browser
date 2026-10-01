///|
let url : String = "http://127.0.0.1:41612/?t=abc&x=1#s=s1"

///|
test "each platform's opener" {
  @debug.assert_eq(commands(MacOS, url, env={}), Ok([["open", url]]))
  @debug.assert_eq(
    commands(Windows, url, env={}),
    Ok([["rundll32", "url.dll,FileProtocolHandler", url]]),
  )
  @debug.assert_eq(
    commands(Linux, url, env={ "DISPLAY": ":0" }),
    Ok([["xdg-open", url]]),
  )
  @debug.assert_eq(
    commands(Linux, url, env={ "WAYLAND_DISPLAY": "wayland-0" }),
    Ok([["xdg-open", url]]),
  )
}

///|
test "WSL opens the Windows browser, with or without a display" {
  let wsl = Ok([["wslview", url], ["explorer.exe", url]])
  @debug.assert_eq(
    commands(Linux, url, env={ "WSL_DISTRO_NAME": "Ubuntu" }),
    wsl,
  )
  @debug.assert_eq(
    commands(Linux, url, env={ "WSL_INTEROP": "/run/WSL/1_interop" }),
    wsl,
  )
}

///|
test "nothing is tried over SSH or without a display, unless forced" {
  @debug.assert_eq(
    commands(MacOS, url, env={ "SSH_CONNECTION": "10.0.0.2 52000 10.0.0.1 22" }),
    Err("over SSH"),
  )
  @debug.assert_eq(
    commands(Linux, url, env={ "DISPLAY": ":0", "SSH_TTY": "/dev/pts/3" }),
    Err("over SSH"),
  )
  @debug.assert_eq(commands(Linux, url, env={}), Err("without a display"))
  // Blank values count as unset; SSH_AUTH_SOCK alone is not a remote session.
  @debug.assert_eq(
    commands(Linux, url, env={
      "DISPLAY": " ",
      "SSH_TTY": "",
      "SSH_AUTH_SOCK": "/tmp/agent",
    }),
    Err("without a display"),
  )
  @debug.assert_eq(
    commands(MacOS, url, env={ "SSH_TTY": "/dev/pts/3" }, force=true),
    Ok([["open", url]]),
  )
  @debug.assert_eq(
    commands(Linux, url, env={}, force=true),
    Ok([["xdg-open", url]]),
  )
}

///|
test "$BROWSER wins, even over SSH" {
  @debug.assert_eq(
    commands(Linux, url, env={ "BROWSER": "firefox", "SSH_TTY": "/dev/pts/3" }),
    Ok([["firefox", url]]),
  )
  // `%s` marks where the URL goes; otherwise it is appended. Entries are
  // tried in order.
  @debug.assert_eq(
    commands(Linux, url, env={ "BROWSER": "w3m -o x %s:open-in-tab" }),
    Ok([["w3m", "-o", "x", url], ["open-in-tab", url]]),
  )
  // Windows separates entries with `;`.
  @debug.assert_eq(
    commands(Windows, url, env={ "BROWSER": "chrome;edge" }),
    Ok([["chrome", url], ["edge", url]]),
  )
  // A blank or empty-entry $BROWSER is ignored.
  @debug.assert_eq(
    commands(MacOS, url, env={ "BROWSER": " : " }),
    Ok([["open", url]]),
  )
}

///|
async test "open starts the first command that exists" {
  // `true` stands in for a browser: it exists and exits at once.
  assert_eq(open(url, env={ "BROWSER": "true" }), Launched)
  assert_eq(
    open(url, env={ "BROWSER": "open-in-browser-no-such-command:true" }),
    Launched,
  )
  assert_eq(
    open(url, env={ "BROWSER": "open-in-browser-no-such-command" }),
    Failed("`open-in-browser-no-such-command` not found"),
  )
}

///|
async test "open reports a skip without starting anything" {
  match @async.platform {
    // Linux decides by display; the other platforms always have one.
    Linux => assert_eq(open(url, env={}), Skipped("without a display"))
    _ => ()
  }
  assert_eq(open(url, env={ "SSH_TTY": "/dev/pts/3" }), Skipped("over SSH"))
}
