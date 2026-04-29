---@diagnostic disable: redefined-local

local U = require 'manipulator.utils'
local RM = require 'manipulator.range_mods'

---@class manipulator
---@field batch manipulator.Batch.module
---@field call_path manipulator.CallPath.module
---@field region manipulator.Region.module
---@field ts manipulator.TS.module
---@field private default_config manipulator.Config
---@field private config manipulator.Config
local M = {
	-- as class names, because there is no static wrapper
	Range = require 'manipulator.range',
	Pos = require 'manipulator.pos',
	RM = RM,
	U = U,
}

--- Configs for all submodules, that can have the following sections:
--- 1. class options - default opts inherited by everyone in the module
--- 2. action defaults - default options for individual class methods
--- 3. module config - options specific for overall module behaviour
--- 4. module function defaults - default options for top-level static actions
--- 5. presets - ready-to-use+template class configs (opts+actions)
---@class manipulator.Config
---@field batch? manipulator.Batch.module.Config
---@field region? manipulator.Region.module.Config
---@field ts? manipulator.TS.module.Config
---@field call_path? manipulator.CallPath.Config

---@type manipulator.Config
M.default_config = {
	batch = {
		inherit = false,
		on_nil_item = 'drop_all',

		pick = {
			format_item = tostring,
			picker = 'native',
			prompt = 'Choose item',
			prompt_postfix = ': ',
			multi = false,
			fzf_resolve_timeout = 100,
			callback = false,
		},

		collect = {
			limit = 500,
		},
	},

	call_path = {
		inherit = false,
		immutable = true,

		call = { on_no_fn = 'error' },
		exec = {
			allow_field_access = false,
			skip_anchors = true,
			skip_empty_motion = true,
		},
		as_op = { except = false, return_expr = false },
		on_short_motion = 'last-or-self',
	},

	region = {
		inherit = false,

		jump = { rangemod = { [10] = RM.trimmed } },
		select = { linewise = 'auto', end_ = true },
		swap = { visual = true, cursor_with = 'current' },

		current = { fallback = '.', end_shift_ptn = '^[, )%]}>]?$' },
	},

	ts = {
		inherit = false,
		langs = { ['*'] = true, 'luap', 'printf', 'regex' },
		types = {
			['*'] = true,
			-- most common node types directly in the defaults
			'_content$',

			-- C/C++
			'compound_statement',
			-- Lua
			'block',
			-- 'dot_index_expression', -- = field paths
			'method_index_expression',
			'arguments',
			'parameters',
		},
		nil_wrap = true, -- TODO: move this option to Region

		field = { types = { ['*'] = true } }, -- by default disable type filtering on field access
		sibling = { types = { inherit = true, comment = false } },
		next = { vertical = 'child' },
		prev = { vertical = 'parent' },

		use_lang_presets = 'ltree_or_buf',

		current = { linewise = false, on_partial = 'larger' },

		presets = {
			-- ### General-use presets
			path = { -- configured for selecting individual fields in a path to an attribute (A.b.c.d=2)
				in_graph = {
					max_link_dst = 4,
					min_depth = -3,
					max_depth = 1,
					langs = { inherit = true, luadoc = false },
				},
				prev = { vertical = false }, -- to override the default setting for both individually
				next = { vertical = false },
			},

			with_docs = { -- select the node under cursor and all documentation associated with it
				nil_wrap = false,

				types = { 'definition$', 'declaration$', '.*comment.*', '.*asignment.*' },
				select = { -- what can we apply the mod to
					rangemod = { inherit = true, [10] = RM.with_docs }, -- specific index to make it last
					langs = { inherit = true, matchers = { ['.*doc.*'] = false } },
				},
				-- which preceeding nodes can join the selection (docs/comments)
				prev_sibling = { langs = false, types = { '.*comment.*' } },
				next_sibling = { types = { inherit = 'self' } }, -- skip inheriting sibling.types
			},

			-- ### Lang presets (used if .use_lang_presets)
			markdown = {
				types = {
					-- `true` always means _inherit from what parent table inherits (→'active' = base cfg)_
					-- in setup config, however, you must use the preset name to avoid ambiguity
					inherit = true,
					'list_marker_minus',
					'inline',
					'block_continuation',
					'delimiter$',
					'marker$',
				},
			},
			lua = {
				types = {
					inherit = true,
					'documentation',
					'_annotation$',
					'chunk',
					'variable_list',
					'expression_list',
				},
			},
		},
	},
}

M.setup_order = { 'batch', 'call_path', 'region', 'ts' }
for _, name in ipairs(M.setup_order) do
	local m = require('manipulator.' .. name)
	M[name] = m
	m.default_config = M.default_config[name]
	m.config = m.default_config
	-- create self-reference
	if not m.config.presets then m.config.presets = {} end
	m.config.presets.default = m.config
	m.config.presets.active = m.config
end

---@param config? manipulator.Config
---@return manipulator
function M.setup(config)
	config = config or {}

	for _, name in ipairs(M.setup_order) do
		local m = require('manipulator.' .. name)
		m.config = U.module_setup( --
			m.config.presets,
			m.config.presets.default,
			config[name],
			m.class.action_map or {}
		)
		if rawget(m, '_post_setup') then m._post_setup() end
	end

	return M
end

---@type manipulator.Config updates the real config at the changed indexes
M.dyn_config = setmetatable({ state = {} }, {
	__index = function(self, k)
		self.active[k] = {}
		self.active = self.active[k]
		return self
	end,
	__newindex = function(self, k, v)
		self.active[k] = v
		M.setup(self.state)
		self.state = {}
		self.active = self.state
	end,
})
---@diagnostic disable-next-line: undefined-field
rawset(M.dyn_config, 'active', M.dyn_config.state)

return M
