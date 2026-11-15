-- Violation: a which-key group label for a prefix no key uses.
table.insert(require('czernous.keymaps').prefixes, { '<leader>z', group = 'tripwire: nothing lives here' })
return {}
