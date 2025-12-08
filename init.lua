local modname = core.get_current_modname()
local modpath = core.get_modpath(modname)
local S = core.get_translator(modname)
local F = core.formspec_escape

local http = core.request_http_api()
if not http then
    error("Add `wordle` into `secure.http_mods` for better experience!")
end

loadfile(modpath .. "/api.lua")(http)

core.register_chatcommand("wordle", {
    description = S("Opens Worlanti main menu"),
    func = function(name)
        local fs = [[
            formspec_version[6]
            size[6,5]
            image[0,0.1;6,1.35;wordle_logo.png]
            button[1,2;4,1;online;%s]
            tooltip[online;%s]
            button[1,3.25;4,1;random;%s]
        ]]

        core.show_formspec(name, "wordle:menu", fs:format(
            F(S("Online words")),
            F(S("Online words are made by players, and moderated by mod creator")),
            F(S("Random word"))
        ))
    end
})

core.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "wordle:menu" then return end

    local name = player:get_player_name()
    if fields.online then
        if not core.is_singleplayer() then wordle.open_online_words(name)
        else core.chat_send_player(name, core.colorize("red", S("Online features are only available in multiplayer due to security concerns."))) end
    end
    if fields.random then
        wordle.random_word(name, function(word)
            wordle.start_game(name, word, 6)
        end)
    end
end)

core.register_on_joinplayer(function(plr)
    local name = plr:get_player_name();
    local meta = plr:get_meta()
    local session = meta:get_string(wordle.meta_key)

    if session ~= "" then
        wordle.sessions[name] = session
    end
end)