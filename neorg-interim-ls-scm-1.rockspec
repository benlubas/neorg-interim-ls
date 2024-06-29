local MODREV, SPECREV = "scm", "-1"
rockspec_format = "3.0"
package = "neorg-interim-ls"
version = MODREV .. SPECREV

description = {
	summary = "A small \"language server\" for Neorg",
	labels = { "neovim" },
	homepage = "https://github.com/benluas/neorg-interim-ls",
	license = "MIT",
}

source = {
	url = "http://github.com/benlubas/neorg-interim-ls/archive/v" .. MODREV .. ".zip",
}

if MODREV == "scm" then
	source = {
		url = "git://github.com/benlubas/neorg-interim-ls",
	}
end

dependencies = {
	"neorg ~> 8",
}
