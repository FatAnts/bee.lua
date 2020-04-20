local lm = require 'luamake'

lm.gcc = 'clang'
lm.gxx = 'clang++'

lm:source_set 'source_lua' {
    rootdir = '3rd/lua/src',
    sources = {
        "*.c",
        "!luac.c",
        "!lua.c",
    },
    defines = {
        "LUA_USE_LINUX",
    },
    visibility = "default",
}

lm:executable 'lua' {
    rootdir = '3rd/lua/src',
    deps = "source_lua",
    sources = {
        "lua.c",
    },
    ldflags = "-Wl,-E",
    defines = {
        "LUA_USE_LINUX",
    },
    links = { "m", "dl" },
}

lm:shared_library 'bee' {
    includes = {
        "3rd/lua/src",
        "3rd/lua-seri",
        "."
    },
    defines = {
        "span_FEATURE_BYTE_SPAN=1"
    },
    sources = {
        "3rd/lua-seri/*.c",
        "bee/*.cpp",
        "binding/*.cpp",
        "!bee/*_win.cpp",
        "!bee/*_osx.cpp",
        "!binding/lua_unicode.cpp",
        "!binding/lua_registry.cpp",
    },
    links = {
        "pthread",
        "stdc++fs",
        "stdc++"
    }
}

lm:executable 'bootstrap' {
    deps = "source_lua",
    includes = {
        "3rd/lua/src"
    },
    sources = {
        "bootstrap/*.cpp",
    },
    ldflags = "-Wl,-E",
    defines = {
        "LUA_USE_LINUX",
    },
    links = { "m", "dl" },
}

local fs = require "bee.filesystem"

lm:build "copy_script" {
    "mkdir", "-p", "$bin", "&&",
    "cp", fs.path "bootstrap/main.lua", "$bin/main.lua"
}

lm:build "test" {
    "$bin/bootstrap", fs.path "test/test.lua",
    deps = { "bootstrap", "copy_script", "bee" },
}
