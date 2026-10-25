import Foundation

/// The `wsh` arguments that continue a session in Wave as if the user had opened a terminal and
/// pasted the command: an ordinary shell block (Wave's rc, header and restart behaviour) whose
/// init script runs the command at the first prompt, once the user's own rc has set PATH.
/// Wave sources the init script before the user's rc, so it only arms a one-shot hook. The hook
/// first drops the script from the block, so restarting the block or Wave doesn't run it again.
public enum WaveResume {
    /// Init-script keys by shell; Wave picks the one for the block's shell.
    static let keys = ["cmd:initscript.zsh", "cmd:initscript.bash", "cmd:initscript.fish"]

    public static func createBlockArgs(_ cmd: String, cwd: String?) -> [String] {
        let quoted = shellQuote(cmd)
        let clear = "wsh setmeta -b \"$WAVETERM_BLOCKID\" " + keys.map { "\($0)=null" }.joined(separator: " ")
        let zsh = """
            _yaak_resume() {
              add-zle-hook-widget -d line-init _yaak_resume
              \(clear) >/dev/null 2>&1 &!
              BUFFER=\(quoted)
              zle .accept-line
            }
            autoload -Uz add-zle-hook-widget
            zle -N _yaak_resume
            add-zle-hook-widget line-init _yaak_resume

            """
        // bash-preexec (loaded by Wave after the user's rc) keeps an existing precmd_functions.
        let bash = """
            _yaak_resume() {
              precmd_functions=("${precmd_functions[@]/_yaak_resume}")
              \(clear) >/dev/null 2>&1 &
              local c=\(quoted)
              history -s "$c"; printf '%s\\n' "$c"; eval "$c"
            }
            precmd_functions+=(_yaak_resume)

            """
        let fish = """
            function _yaak_resume --on-event fish_prompt
              functions -e _yaak_resume
              \(clear) >/dev/null 2>&1 &
              set -l c \(quoted)
              echo $c; eval $c
            end

            """
        var args = ["createblock", "term", "controller=shell"]
        if let cwd { args.append("cmd:cwd=\(json(cwd))") }
        for (key, script) in zip(keys, [zsh, bash, fish]) { args.append("\(key)=\(json(script))") }
        return args
    }

    /// `wsh` reads a value starting with `"` as JSON, so any text arrives as is.
    static func json(_ s: String) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = .withoutEscapingSlashes
        return String(decoding: (try? enc.encode(s)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}
