# bobzhang/open_in_browser

Open a URL in the default web browser from a MoonBit program, on macOS, Linux
(including WSL) and Windows. Works on the native and wasm (`moonrun`) targets.

```bash
moon add bobzhang/open_in_browser
```

```moonbit
async fn main {
  match @open_in_browser.open("http://127.0.0.1:8080/") {
    Launched => println("opened it in your browser")
    Skipped(why) => println("not opening a browser \{why}; open the link yourself")
    Failed(error) => println("could not open a browser (\{error})")
  }
}
```

`open` never blocks and never writes to your terminal. The opener is started
detached and not waited on, and its output goes to the null device, so it is
safe to call from a TUI.

## What it runs

| Where | Command |
| --- | --- |
| `$BROWSER` set | each `:`-separated entry in turn (`;` on Windows); `%s` is replaced by the URL, otherwise the URL is appended |
| macOS | `open <url>` |
| Windows | `rundll32 url.dll,FileProtocolHandler <url>`: one argument, no shell, so `?`, `&` and `#` are safe |
| Linux under WSL | `wslview <url>`, then `explorer.exe <url>` |
| Linux | `xdg-open <url>` |

`open` is used only on macOS, because on Linux that name can belong to another
program (`openvt`).

## When it does not try

- **Over SSH** (`SSH_CONNECTION` or `SSH_TTY` set), where the browser would
  open on the remote machine: `Skipped("over SSH")`.
- **On Linux without a display** (no `DISPLAY` or `WAYLAND_DISPLAY`, and not
  WSL): `Skipped("without a display")`.

Pass `force=true` to try anyway. `$BROWSER` is always honoured, since it is the
user's own choice.

## API

- `open(url, force?, env?) -> Outcome` (async): try the commands in order until
  one starts. `env` defaults to the process environment.
- `commands(platform, url, env~, force?) -> Result[Array[Array[String]], String]`:
  the decision alone, without starting anything, to show or test.
- `Outcome`: `Launched`, `Skipped(reason)` or `Failed(error)`. `Launched` means
  an opener was started, not that a window appeared.

## License

Apache-2.0
