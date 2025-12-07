local http = ...

local modname = core.get_current_modname()
local S = core.get_translator(modname)
local F = core.formspec_escape

local function show_loading(name)
    core.show_formspec(name, "wordle:loading",
        "formspec_version[6]size[2,2]no_prepend[]bgcolor[#FFFFFF;true]" ..
        "animated_image[0.5,0.5;1,1;spinner;wordle_loading.png;4;84]"
    )
end

function wordle.check_word_online(name, word, callback)
    show_loading(name)
    local url = "https://api.dictionaryapi.dev/api/v2/entries/en/" .. word

    http.fetch({ url = url, timeout = 5 }, function(result)
        if result.succeeded and result.code == 200 then
            callback(true)
        else
            callback(false)
        end
    end)
end

function wordle.random_word(name, callback)
    show_loading(name)

    local url = "https://skybuilder.synology.me/wordle/daily/"

    http.fetch({ url = url, timeout = 5 }, function(result)
        callback(core.parse_json(result.data).word)
    end)
end

local function make_formspec(state)
    local letters = state.letters
    local attempt = state.attempt
    local word = state.word
    local grid = ""
    
    for row = 1, state.max_attempts do
        local row_letters = letters[row] or {}

        for col = 1, #word do
            local tex = "wordle_background.png"

            local letter = row_letters[col]
            if letter then
                local color = state.colors[row] and state.colors[row][col]
                tex = tex .. "^wordle_" .. color .. ".png^wordle_letter_" .. letter .. ".png"
            end

            grid = grid ..
                string.format("image[%f,%f;1,1;%s]",
                    (col - 1) + 0.5 + (0.25 * (col - 1)),
                    (row - 1) + 0.5 + (0.075 * (row - 1)),
                    tex
                )
        end
    end

    return ("formspec_version[6]" ..
           "size[7,10]" ..
           grid ..
           "field[0.25,7.5;6.5,1;guess;%s;" ..
           "]" ..
           "button[0.25,8.75;3,1;submit;%s]" ..
           "button_exit[3.75,8.75;3,1;exit;%s]"):format(
            F(S("Enter word:")),
            F(S("Submit")),
            F(S("Exit"))
           )
end

local function evaluate_guess(guess, word)
    local result = {}
    local word_temp = {}

    for i = 1, #word do
        word_temp[i] = word:sub(i,i)
    end

    for i = 1, #word do
        if guess:sub(i,i) == word:sub(i,i) then
            result[i] = "green"
            word_temp[i] = nil
        end
    end

    for i = 1, #word do
        if not result[i] then
            local g = guess:sub(i,i)
            local found = false
            for j = 1, #word_temp do
                if word_temp[j] == g then
                    found = true
                    word_temp[j] = nil
                    break
                end
            end
            result[i] = found and "yellow" or "grey"
        end
    end

    return result
end

function wordle.start_game(name, word, max_attempts, online)
    word = word:lower()

    wordle.active_games[name] = {
        word = word,
        max_attempts = max_attempts or 6,
        attempt = 1,
        letters = {},
        colors = {},
        online = online
    }

    core.show_formspec(name, "wordle:game", make_formspec(wordle.active_games[name]))
end

local function make_online_formspec(name, data)
    local page = data.page
    local total = data.total_pages
    local words = data.words or {}

    local fs = "formspec_version[6]size[10.5,10]"
    fs = fs .. "label[0.5,0.6;" .. F(S("Online words")) .. "]"

    local positions = {
        {0.5, 1.3}, {5.3, 1.3},
        {0.5, 3.6}, {5.3, 3.6},
        {0.5, 5.9}, {5.3, 5.9},
    }

    for i, pos in ipairs(positions) do
        local item = words[i]
        if item then
            local id = item.id
            local masked = string.rep("*", #item.word)
            fs = fs .. string.format(
                "button[%s,%s;4.7,2.2;w_%d;#%d: %s\\; %s]",
                pos[1], pos[2], id, id, masked, F(S("@1 likes", item.likes))
            )
        end
    end

    local buttons = (
        "button[7,0.3;3,0.8;login;%s]" ..
        "button[3.9,0.3;3,0.8;register;%s]"):format(
            F(S("Login")),
            F(S("Register"))
        )

    if wordle.sessions[name] then
        buttons = (
        "button[7,0.3;3,0.8;publish;%s]" ..
        "button[3.9,0.3;3,0.8;search;%s]"):format(
            F(S("Publish")),
            F(S("Search"))
        )
    end

    fs = (fs ..
        "button[3.9,8.6;3,0.8;previous;<]" ..
        "button[7,8.6;3,0.8;next;>]" ..
        "label[0.5,9;%s]" .. buttons):format(
            F(S("Page @1 of @2", page, total))
        )

    return fs
end

local function is_liked(name, word, callback)
    show_loading(name)

    local url = "https://skybuilder.synology.me/wordle/liked/?word=" .. word .. "&session=" .. wordle.sessions[name]

    http.fetch({ url = url, timeout = 5 }, function(res)
        if not res.succeeded then
            core.chat_send_player(name, "Failed to load likes!")
            return
        end

        local data = core.parse_json(res.data)
        if not data or not res.succeeded then
            core.chat_send_player(name, "Invalid server response!")
            return
        end

        callback(data.liked)
    end)
end

local function like_word(name, word, callback)
    show_loading(name)

    local url = "https://skybuilder.synology.me/wordle/like/?word=" .. word .. "&session=" .. wordle.sessions[name]

    http.fetch({ url = url, timeout = 5 }, function(res)
        if not res.succeeded then
            core.chat_send_player(name, "Failed to like word!")
            return
        end

        local data = core.parse_json(res.data)
        if not data or not res.succeeded then
            core.chat_send_player(name, "Invalid server response!")
            return
        end

        callback()
    end)
end

local function unlike_word(name, word, callback)
    show_loading(name)

    local url = "https://skybuilder.synology.me/wordle/unlike/?word=" .. word .. "&session=" .. wordle.sessions[name]

    http.fetch({ url = url, timeout = 5 }, function(res)
        if not res.succeeded then
            core.chat_send_player(name, "Failed to unlike word!")
            return
        end

        local data = core.parse_json(res.data)
        if not data or not res.succeeded then
            core.chat_send_player(name, "Invalid server response!")
            return
        end

        callback()
    end)
end

local function fetch_online_page(name, page, search, ignore_cache)
    local cache_key = search and ("search:" .. search .. ":" .. page) or ("page:" .. page)

    if wordle.online_cache[cache_key] and not ignore_cache then
        core.show_formspec(name, "wordle:online", make_online_formspec(name, wordle.online_cache[cache_key]))
        wordle.online_page[name] = page
        wordle.online_search[name] = search
        return
    end

    show_loading(name)

    local url = "https://skybuilder.synology.me/wordle/words/?page=" .. page
    if search then
        url = url .. "&search=" .. core.encode_base64(search)
    end

    http.fetch({ url = url, timeout = 5 }, function(res)
        if not res.succeeded then
            core.chat_send_player(name, "Failed to load words!")
            return
        end

        local data = core.parse_json(res.data)
        if not data then
            core.chat_send_player(name, "Invalid server response!")
            return
        end

        wordle.online_cache[cache_key] = data
        wordle.online_page[name] = page
        wordle.online_search[name] = search

        core.show_formspec(name, "wordle:online", make_online_formspec(name, data))
    end)
end

function wordle.show_search(name)
    local fs = [[
        formspec_version[6]
        size[6,3]
        field[0.3,0.5;5.4,1;query;%s;]
        button[0.3,1.75;2.5,1;submit;%s]
        button_exit[3.2,1.75;2.5,1;exit;%s]
    ]]

    core.show_formspec(name, "wordle:search", fs:format(
        F(S("Search:")),
        F(S("Submit")),
        F(S("Close"))
    ))
end

function wordle.show_word_info(name, item, liked)
    local text = S(
        "<b>ID:</b> #@1@n<b>Word:</b> @2@n<b>Max</b>: @3 attempts@n<b>Author:</b> @4@n<b>Created:</b> @5@n<b>Description:</b> @6",
        item.id or "?",
        string.rep("*", #item.word),
        item.max_attempts or 6,
        item.author or "Unknown",
        item.created_at or "Unknown",
        item.description or "—"
    )

    local fs = [[
        formspec_version[6]
        size[8,8]
        hypertext[0.2,0.2;7.6,6.2;info;%s]
        button[0.2,6.6;3.7,1.3;play;%s]
        %s
    ]]

    wordle.current_info[name] = item
    core.show_formspec(name, "wordle:info", fs:format(
        F(text),
        F(S("Play")),
        (wordle.sessions[name] and "button[4.1,6.6;3.7,1.3;" .. ((liked and "unlike") or "like") .. ";" .. ((liked and F(S("Unlike"))) or F(S("Like"))) .. "]") or ""
    ))
end

function wordle.show_register(name, error_msg)
    local fs = [[
        formspec_version[6]
        size[6,7]
        label[0.3,0.375;Register]
        field[0.3,1.2;5.4,1;username;%s;]
        pwdfield[0.3,2.7;5.4,1;password;%s]
        button[0.3,4;5.4,1;submit;%s]
        button_exit[0.3,5.2;5.4,1;exit;%s]
    ]]

    if error_msg then
        fs = fs .. "label[0.3,6.5;" .. core.colorize("#FF0000", F(error_msg)) .. "]"
    end

    core.show_formspec(name, "wordle:register", fs:format(
        F(S("Username")),
        F(S("Password")),
        F(S("Register")),
        F(S("Close"))
    ))
end

local function register_account(name, username, password)
    show_loading(name)

    local ip = core.get_player_ip(name) or "1.0.0.1"
    http.fetch({
        url = "https://skybuilder.synology.me/wordle/register/?username=" .. username .. "&password=" .. password .. "&ip=" .. ip,
        timeout = 5
    }, function(res)
        local data = core.parse_json(res.data or "{}")

        if not res.succeeded or data.error then
            wordle.show_register(name, data.error or "Server error")
            return
        end

        core.chat_send_player(name, "Registration successful!")
        wordle.show_login(name)
    end)
end

local function publish_word(name, word, description, max_attempts)
    show_loading(name)

    http.fetch({
        url = "https://skybuilder.synology.me/wordle/publish/?word=" .. word .. "&description=" .. core.encode_base64(description) .. "&attempts=" .. max_attempts .. "&session=" .. wordle.sessions[name],
        timeout = 5
    }, function(res)
        local data = core.parse_json(res.data or "{}")

        if not res.succeeded or data.error then
            wordle.show_publish(name, data.error or "Server error")
            return
        end

        core.chat_send_player(name, "Publish successful!")
        fetch_online_page(name, 1, nil, true)
    end)
end

function wordle.show_publish(name, error_msg)
    local fs = [[
        formspec_version[6]
        size[10.5,11]
        field[0.3,0.5;9.9,1.2;word;%s:;]
        field[5.3,0.5;4.9,1.2;attempts;%s:;6]
        textarea[0.3,2.2;9.9,6.6;desc;%s:;]
        button[0.3,9.4;4.9,1.4;submit;%s]
        button_exit[5.3,9.4;4.9,1.4;exit;%s]
    ]]

    if error_msg then
        fs = fs .. "label[0.3,9.1;" .. core.colorize("#FF0000", F(error_msg)) .. "]"
    end

    core.show_formspec(name, "wordle:publish", fs:format(
        F(S("Word")),
        F(S("Max Attempts")),
        F(S("Description")),
        F(S("Submit")),
        F(S("Close"))
    ))
end

function wordle.show_login(name, error_msg)
    local fs = [[
        formspec_version[6]
        size[6,7]
        label[0.3,0.375;Login]
        field[0.3,1.2;5.4,1;username;%s;]
        pwdfield[0.3,2.7;5.4,1;password;%s]
        button[0.3,4;5.4,1;submit;%s]
        button_exit[0.3,5.2;5.4,1;exit;%s]
    ]]

    if error_msg then
        fs = fs .. "label[0.3,6.5;" .. core.colorize("#FF0000", F(error_msg)) .. "]"
    end

    core.show_formspec(name, "wordle:login", fs:format(
        F(S("Username")),
        F(S("Password")),
        F(S("Login")),
        F(S("Close"))
    ))
end

local function login_account(name, username, password)
    show_loading(name)

    http.fetch({
        url = "https://skybuilder.synology.me/wordle/login/?username=" .. username .. "&password=" .. password,
        timeout = 5
    }, function(res)
        local data = core.parse_json(res.data or "{}")

        if not res.succeeded or data.error then
            wordle.show_login(name, data.error or "Server error")
            return
        end

        wordle.sessions[name] = data.session

        local player = core.get_player_by_name(name)
        if player then
            player:get_meta():set_string(wordle.meta_key, data.session)
        end

        core.chat_send_player(name, "Login successful!")
        fetch_online_page(name, 1)
    end)
end

core.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()
    if formname == "wordle:game" then
        local game = wordle.active_games[name]
        if not game then return end

        if fields.exit then
            wordle.active_games[name] = nil
            return
        end

        if fields.submit then
            local guess = fields.guess:lower()

            if #guess ~= #game.word then
                return true
            end

            wordle.check_word_online(name, guess, function(exists)
                local row = game.attempt
                game.letters[row] = {}

                for i = 1, #guess do
                    local letter = guess:sub(i,i)
                    if letter:match("%l") then
                        game.letters[row][i] = letter
                    end
                end

                local result = evaluate_guess(guess, game.word)
                game.colors[row] = result

                if guess == game.word then
                    local winfs = "formspec_version[6]"..
                        "size[10.5,11]"..
                        "image[0,0;10.5,5.6;wordle_win.png]"..
                        "button_exit[0.1,9.8;10.3,1.1;exit;" .. F(S("Close")) .. "]" ..
                        "label[0.1,9.5;" .. F(S("The word was: @1", string.upper(game.word))) .. "]"

                    for row = 1, game.max_attempts do
                        local row_letters = game.letters[row] or {}

                        for col = 1, #game.word do
                            local tex = "wordle_background.png"

                            local letter = row_letters[col]
                            if letter then
                                local color = game.colors[row] and game.colors[row][col]
                                tex = tex .. "^wordle_" .. color .. "_mini.png"
                            end

                            winfs = winfs ..
                                string.format("image[%f,%f;0.5,0.5;%s]",
                                    (col - 1) * 0.5 + 4,
                                    (row - 1) * 0.5 + 5.6,
                                    tex
                                )
                        end
                    end

                    core.show_formspec(name, "wordle:win",
                        winfs)
                    wordle.active_games[name] = nil
                    return
                end

                if not exists then
                    game.letters[row] = {}
                    core.chat_send_player(name, core.colorize("red", S("This word does not exist!")))
                    core.show_formspec(name, "wordle:game", make_formspec(game))
                    return
                end

                game.attempt = game.attempt + 1

                if game.attempt > game.max_attempts then
                    local losefs = "formspec_version[6]"..
                        "size[10.5,11]"..
                        "image[0,0;10.5,5.6;wordle_lose.png]"..
                        "button_exit[0.1,9.8;10.3,1.1;exit;" .. F(S("Close")) .. "]" ..
                        "label[0.1,9.5;" .. F(S("The word was: @1", string.upper(game.word))) .. "]"

                    for row = 1, game.max_attempts do
                        local row_letters = game.letters[row] or {}

                        for col = 1, #game.word do
                            local tex = "wordle_background.png"

                            local letter = row_letters[col]
                            if letter then
                                local color = game.colors[row] and game.colors[row][col]
                                tex = tex .. "^wordle_" .. color .. "_mini.png"
                            end

                            losefs = losefs ..
                                string.format("image[%f,%f;0.5,0.5;%s]",
                                    (col - 1) * 0.5 + 4,
                                    (row - 1) * 0.5 + 5.6,
                                    tex
                                )
                        end
                    end

                    core.show_formspec(name, "wordle:lose", losefs)
                    wordle.active_games[name] = nil
                    return
                end

                core.show_formspec(name, "wordle:game", make_formspec(game))
            end)

            return true
        end

    elseif formname == "wordle:online" then
        local page = wordle.online_page[name] or 1
        local key = wordle.online_search[name]
            and ("search:" .. wordle.online_search[name] .. ":" .. page)
            or  ("page:" .. page)

        local data = wordle.online_cache[key]
        if not data then return end

        for _, item in pairs(data.words) do
            if fields["w_" .. item.id] then
                if wordle.sessions[name] then
                    is_liked(name, item.id, function(liked)
                        wordle.show_word_info(name, item, liked)
                    end)
                else
                    wordle.show_word_info(name, item, false)
                end
                return
            end
        end

        if fields.next then
            local next_page = math.min(page + 1, data.total_pages)
            fetch_online_page(name, next_page, wordle.online_search[name])
            return
        end

        if fields.previous then
            local prev_page = math.max(page - 1, 1)
            fetch_online_page(name, prev_page, wordle.online_search[name])
            return
        end

        if fields.login then
            wordle.show_login(name)
            return
        end

        if fields.register then
            wordle.show_register(name)
            return
        end

        if fields.search then
            wordle.show_search(name)
            return
        end

        if fields.publish then
            wordle.show_publish(name)
            return
        end

    end

    if formname == "wordle:register" then
        if fields.submit then
            register_account(name, fields.username, fields.password)
        end
        return true
    end

    if formname == "wordle:login" then
        if fields.submit then
            login_account(name, fields.username, fields.password)
        end
        return true
    end

    if formname == "wordle:info" then
        local item = wordle.current_info[name]
        if not item then return end

        if fields.play then
            wordle.start_game(name, item.word, tonumber(item.max_attempts))
        end

        if fields.like then
            like_word(name, item.id, function()
                wordle.show_word_info(name, item, true)
            end)
        end

        if fields.unlike then
            unlike_word(name, item.id, function()
                wordle.show_word_info(name, item, false)
            end)
        end

        return true
    end

    if formname == "wordle:search" then
        if fields.submit and fields.query and fields.query ~= "" then
            local query = fields.query

            fetch_online_page(name, 1, query)
        end
        return true
    end

    if formname == "wordle:publish" then
        if fields.submit then
            if string.len(fields.desc) > 255 then
                core.chat_send_player(name, core.colorize("red", S("Description is too big!")))
                return
            elseif string.len(fields.word) ~= 5 then
                core.chat_send_player(name, core.colorize("red", S("The word must be 5 characters long!")))
                return
            elseif not tonumber(fields.attempts) then
                core.chat_send_player(name, core.colorize("red", S("Max attempts is empty!")))
                return
            elseif tonumber(fields.attempts) < 1 or tonumber(fields.attempts) > 6 then
                core.chat_send_player(name, core.colorize("red", S("Max attempts must be between 1 and 6!")))
                return
            end
            publish_word(name, fields.word, fields.desc, fields.attempts)
        end
        return true
    end
end)

function wordle.open_online_words(name)
    fetch_online_page(name, 1)
end