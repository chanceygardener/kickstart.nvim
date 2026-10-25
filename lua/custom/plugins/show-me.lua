-- show-me: terminal agents (Claude Code, Codex, Cursor) open code here while
-- they explain it. It lives in its own repository; the build hook installs the
-- matching `show-me` CLI and links the agent skill. Switch `dir` to
-- 'chanceygardener/show-me' once it is published.
return {
  dir = '~/repos/show-me',
  name = 'show-me',
  event = 'VeryLazy',
  build = function(plugin)
    local result = vim.system({ 'sh', plugin.dir .. '/install.sh', '--for-plugin', plugin.dir }, { text = true }):wait()
    assert(result.code == 0, result.stderr)
  end,
  opts = {},
}
