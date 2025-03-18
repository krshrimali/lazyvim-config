-- since this is just an example spec, don't actually load anything here and return an empty spec
-- stylua: ignore
-- if true then return {} end

-- every spec file under the "plugins" directory will be loaded automatically by lazy.nvim
--
-- In your plugin files, you can:
-- * add extra plugins
-- * disable/enabled LazyVim plugins
-- * override the configuration of LazyVim plugins
return {
    -- add gruvbox
    { "ellisonleao/gruvbox.nvim" },

    -- Configure LazyVim to load gruvbox
    -- {
    --   "LazyVim/LazyVim",
    --   opts = {
    --     colorscheme = "gruvbox",
    --   },
    -- },

    -- change trouble config
    -- {
    --   "folke/trouble.nvim",
    --   -- opts will be merged with the parent spec
    --   opts = { use_diagnostic_signs = true },
    -- },

    -- disable trouble
    -- { "folke/trouble.nvim", enabled = false },

    -- override nvim-cmp and add cmp-emoji
    --
    --
    -- {
    -- "hrsh7th/nvim-cmp",
    -- ---@param opts cmp.ConfigSchema
    -- opts = function(_, opts)
    --   local has_words_before = function()
    --     unpack = unpack or table.unpack
    --     local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    --     return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
    --   end
    --
    --   local cmp = require("cmp")
    --
    --   opts.mapping = vim.tbl_extend("force", opts.mapping, {
    --     ["<Tab>"] = cmp.mapping(function(fallback)
    --       if cmp.visible() then
    --         -- You could replace select_next_item() with confirm({ select = true }) to get VS Code autocompletion behavior
    --         cmp.select_next_item()
    --       elseif vim.snippet.active({ direction = 1 }) then
    --         vim.schedule(function()
    --           vim.snippet.jump(1)
    --         end)
    --       elseif has_words_before() then
    --         cmp.complete()
    --       else
    --         fallback()
    --       end
    --     end, { "i", "s" }),
    --     ["<S-Tab>"] = cmp.mapping(function(fallback)
    --       if cmp.visible() then
    --         cmp.select_prev_item()
    --       elseif vim.snippet.active({ direction = -1 }) then
    --         vim.schedule(function()
    --           vim.snippet.jump(-1)
    --         end)
    --       else
    --         fallback()
    --       end
    --     end, { "i", "s" }),
    --   })
    -- end,
    -- },
    --
    -- {
    --   "hrsh7th/nvim-cmp",
    --   dependencies = { "hrsh7th/cmp-emoji" },
    --   ---@param opts cmp.ConfigSchema
    --   opts = function(_, opts)
    --     table.insert(opts.sources, { name = "emoji" })
    --   end,
    -- },

    -- change some telescope options and a keymap to browse plugin files
    -- {
    --   "nvim-telescope/telescope.nvim",
    --   keys = {
    --     -- add a keymap to browse plugin files
    --     -- stylua: ignore
    --     {
    --       "<leader>fp",
    --       function() require("telescope.builtin").find_files({ cwd = require("lazy.core.config").options.root }) end,
    --       desc = "Find Plugin File",
    --     },
    --   },
    --   -- change some options
    --   opts = {
    --     defaults = {
    --       layout_strategy = "horizontal",
    --       layout_config = { prompt_position = "top" },
    --       sorting_strategy = "ascending",
    --       winblend = 0,
    --     },
    --   },
    -- },

    -- add pyright to lspconfig
    {
        "neovim/nvim-lspconfig",
        ---@class PluginLspOpts
        opts = {
            ---@type lspconfig.options
            servers = {
                -- pyright will be automatically installed with mason and loaded with lspconfig
                pyright = {
                    settings = {
                        pyright = {
                            disableOrganizeImports = true,
                        },
                        python = {
                            analysis = {
                                ignore = { "*" },
                            }
                        }
                    }
                },
            },
        },
    },

    -- add tsserver and setup with typescript.nvim instead of lspconfig
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "jose-elias-alvarez/typescript.nvim",
            init = function()
                require("lazyvim.util").lsp.on_attach(function(_, buffer)
                    -- stylua: ignore
                    vim.keymap.set("n", "<leader>co", "TypescriptOrganizeImports",
                        { buffer = buffer, desc = "Organize Imports" })
                    vim.keymap.set("n", "<leader>cR", "TypescriptRenameFile", { desc = "Rename File", buffer = buffer })
                end)
            end,
        },
        ---@class PluginLspOpts
        opts = {
            ---@type lspconfig.options
            servers = {
                -- tsserver will be automatically installed with mason and loaded with lspconfig
                tsserver = {},
            },
            -- you can do any additional lsp server setup here
            -- return true if you don't want this server to be setup with lspconfig
            ---@type table<string, fun(server:string, opts:_.lspconfig.options):boolean?>
            setup = {
                -- example to setup with typescript.nvim
                tsserver = function(_, opts)
                    require("typescript").setup({ server = opts })
                    return true
                end,
                -- Specify * to use this function as a fallback for any server
                -- ["*"] = function(server, opts) end,
            },
        },
    },

    -- for typescript, LazyVim also includes extra specs to properly setup lspconfig,
    -- treesitter, mason and typescript.nvim. So instead of the above, you can use:
    { import = "lazyvim.plugins.extras.lang.typescript" },

    -- add more treesitter parsers
    {
        "nvim-treesitter/nvim-treesitter",
        opts = {
            ensure_installed = {
                "bash",
                "html",
                "javascript",
                "json",
                "lua",
                "markdown",
                "markdown_inline",
                "python",
                "query",
                "regex",
                "tsx",
                "typescript",
                "vim",
                "yaml",
            },
        },
    },

    -- since `vim.tbl_deep_extend`, can only merge tables and not lists, the code above
    -- would overwrite `ensure_installed` with the new value.
    -- If you'd rather extend the default config, use the code below instead:
    {
        "nvim-treesitter/nvim-treesitter",
        opts = function(_, opts)
            -- add tsx and treesitter
            vim.list_extend(opts.ensure_installed, {
                "tsx",
                "typescript",
            })
        end,
    },

    -- the opts function can also be used to change the default opts:
    -- {
    --   "nvim-lualine/lualine.nvim",
    --   event = "VeryLazy",
    --   opts = function(_, opts)
    --     table.insert(opts.sections.lualine_x, {
    --       function()
    --         return "😄"
    --       end,
    --     })
    --   end,
    -- },
    --
    -- -- or you can return new options to override all the defaults
    -- {
    --   "nvim-lualine/lualine.nvim",
    --   event = "VeryLazy",
    --   opts = function()
    --     return {
    --       --[[add your custom lualine config here]]
    --     }
    --   end,
    -- },

    -- use mini.starter instead of alpha
    -- { import = "lazyvim.plugins.extras.ui.mini-starter" },

    -- add jsonls and schemastore packages, and setup treesitter for json, json5 and jsonc
    { import = "lazyvim.plugins.extras.lang.json" },
    {
        "ibhagwan/fzf-lua",
        opts = {
            defaults = {
                git_icons = false,
            },
        },
    },

    -- add any tools you want to have installed below
    {
        "williamboman/mason.nvim",
        opts = {
            ensure_installed = {
                "stylua",
                "shellcheck",
                "shfmt",
                "flake8",
            },
        },
    },

    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        opts = {
            scope = { enabled = true },
            dim = { enabeld = true },
            -- scroll = { enabled = true },
            gitbrowse = {
                what = "permalink",
                url_patterns = {
                    ["github%.deshaw%.com"] = {
                        branch = "/tree/{branch}",
                        file = "/blob/{branch}/{file}#L{line_start}-L{line_end}",
                        permalink = "/blob/{commit}/{file}#L{line_start}-L{line_end}",
                        commit = "/commit/{commit}",
                    },
                },
            },
        },
    },

    {
        "folke/noice.nvim",
        opts = function(_, opts)
            opts.lsp.signature = {
                auto_open = { enabled = false },
            }
        end,
    },
    {
        "nvim-zh/colorful-winsep.nvim",
        config = true,
        event = { "WinLeave" },
    },
    {
        "neoclide/coc.nvim",
        branch = "release",
    },

    {
        "TabbyML/vim-tabby",
        lazy = false,
        dependencies = {
            "neovim/nvim-lspconfig",
        },
        init = function()
            vim.g.tabby_agent_start_command = { "npx", "tabby-agent", "--stdio" }
            vim.g.tabby_inline_completion_trigger = "auto"
        end,
    },
    -- {
    --   "yetone/avante.nvim",
    --   event = "VeryLazy",
    --   lazy = false,
    --   version = false, -- Set this to "*" to always pull the latest release version, or set it to false to update to the latest code changes.
    --   opts = {
    --     provider = "copilot",
    --   },
    --   -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    --   build = "make",
    --   -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
    --   dependencies = {
    --     "stevearc/dressing.nvim",
    --     "nvim-lua/plenary.nvim",
    --     "MunifTanjim/nui.nvim",
    --     --- The below dependencies are optional,
    --     "echasnovski/mini.pick", -- for file_selector provider mini.pick
    --     "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
    --     "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
    --     "ibhagwan/fzf-lua", -- for file_selector provider fzf
    --     "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
    --     "zbirenbaum/copilot.lua", -- for providers='copilot'
    --     {
    --       -- support for image pasting
    --       "HakonHarnes/img-clip.nvim",
    --       event = "VeryLazy",
    --       opts = {
    --         -- recommended settings
    --         default = {
    --           embed_image_as_base64 = false,
    --           prompt_for_file_name = false,
    --           drag_and_drop = {
    --             insert_mode = true,
    --           },
    --           -- required for Windows users
    --           use_absolute_path = true,
    --         },
    --       },
    --     },
    --     {
    --       -- Make sure to set this up properly if you have lazy=true
    --       'MeanderingProgrammer/render-markdown.nvim',
    --       opts = {
    --         file_types = { "markdown", "Avante" },
    --       },
    --       ft = { "markdown", "Avante" },
    --     },
    --   },
    -- },

    -- filetype plugin on
    --
    -- " Section for plugins managed by vim-plug
    -- call plug#begin('~/.vim/plugged')
    --
    -- " Tabby plugin
    -- Plug 'TabbyML/vim-tabby'
    -- " Add config here. Example config:
    -- let g:tabby_keybinding_accept = '<Tab>'
    --
    -- " Configure node >= 18
    -- let g:tabby_node_binary = '/prod/tools/infra/nodejs/node20/node/bin/node'
    --
    -- call plug#end()
}
