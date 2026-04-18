-- ModernZ v0.2.9 (https://github.com/Samillion/ModernZ)
--
-- This script is a derivative of the original mpv-osc-modern by maoiscat
-- and subsequent forks:
--   * cyl0/ModernX
--   * dexeonify/ModernX
--
-- It is based on the official osc.lua from mpv, licensed under the
-- GNU Lesser General Public License v2.1 (LGPLv2.1).
-- Preserve this notice and the upstream attribution when redistributing this
-- file or derivative works. Distributions should also include a local copy of
-- the LGPLv2.1 license text alongside the repository/package.
-- Reference license text:
--   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

local assdraw = require("mp.assdraw")
local msg = require("mp.msg")
local opt = require("mp.options")
local utils = require("mp.utils")

-- Parameters
-- default user option values
-- do not touch, change them in modernz.conf
local user_opts = {
	-- Language and display
	language = "en", -- set language (for available options, see: https://github.com/Samillion/ModernZ/blob/main/docs/TRANSLATIONS.md)
	icon_theme = "fluent", -- set icon theme. accepts "fluent" or "material"
	font = "mpv-osd-symbols", -- font for the OSC (default: mpv-osd-symbols or the one set in mpv.conf)

	idlescreen = true, -- show mpv logo when idle
	window_top_bar = "auto", -- show OSC window top bar: "auto", "yes", or "no" (borderless/fullscreen)
	showwindowed = true, -- show OSC when windowed
	showfullscreen = true, -- show OSC when fullscreen
	showonpause = true, -- show OSC when paused
	keeponpause = true, -- disable OSC hide timeout when paused
	greenandgrumpy = false, -- disable Santa hat in December

	-- OSC behaviour and scaling
	hidetimeout = 1500, -- time (in ms) before OSC hides if no mouse movement
	seek_resets_hidetimeout = true, -- if seeking should reset the hidetimeout
	fadeduration = 200, -- fade-out duration (in ms), set to 0 for no fade
	fadein = false, -- whether to enable fade-in effect
	minmousemove = 0, -- minimum mouse movement (in pixels) required to show OSC
	bottomhover = true, -- show OSC only when hovering at the bottom
	bottomhover_zone = 130, -- height of hover zone for bottomhover (in pixels)
	osc_on_seek = false, -- show OSC when seeking
	osc_on_start = false, -- show OSC on start of every file
	osc_keep_with_cursor = true, -- keep OSC visible if mouse cursor is within OSC boundaries
	mouse_seek_pause = true, -- pause video while seeking with mouse move (on button hold)
	force_seek_tooltip = false, -- force show seekbar tooltip on mouse drag, even if not hovering seekbar

	vidscale = "auto", -- scale osc with the video
	scalewindowed = 1.0, -- osc scale factor when windowed
	scalefullscreen = 1.0, -- osc scale factor when fullscreen

	-- Elements display
	show_title = true, -- show title in the OSC (above seekbar)
	title = "${media-title}", -- title above seekbar format: "${media-title}" or "${filename}"
	title_font_size = 24, -- title font size (above seekbar)
	chapter_title_font_size = 14, -- chapter title font size

	cache_info = false, -- show cached time information
	cache_info_speed = false, -- show cache speed per second
	cache_info_font_size = 12, -- font size of the cache information

	show_chapter_title = true, -- show chapter title (above seekbar)
	chapter_fmt = "%s", -- format for chapter display on seekbar hover (set to "no" to disable)

	timetotal = true, -- show total time instead of remaining time
	timems = false, -- show timecodes with milliseconds
	unicodeminus = false, -- use the Unicode minus sign in remaining time
	time_format = "dynamic", -- "dynamic" or "fixed". dynamic shows MM:SS when possible, fixed always shows HH:MM:SS
	time_font_size = 16, -- font size of the time display

	tooltip_font_size = 14, -- tooltips font size

	-- Title bar settings
	show_window_title = false, -- show window title in borderless/fullscreen mode
	window_title = "${media-title}", -- same as title but for window_top_bar
	window_title_font_size = 26, -- window title font size
	window_controls = true, -- show window controls (close, minimize, maximize) in borderless/fullscreen

	-- Subtitle display settings
	raise_subtitles = true, -- raise subtitles above the OSC when shown
	raise_subtitle_amount = 125, -- amount by which subtitles are raised when the OSC is shown (in pixels)

	-- Buttons display and functionality
	jump_buttons = true, -- show the jump backward and forward buttons
	jump_amount = 10, -- change the jump amount in seconds
	jump_more_amount = 60, -- change the jump amount in seconds when right-clicking jump buttons and shift-clicking chapter skip buttons
	jump_icon_number = true, -- show different icon when jump_amount is set to 5, 10, or 30
	jump_mode = "relative", -- seek mode for jump buttons
	jump_softrepeat = true, -- enable continuous jumping when holding down seek buttons
	chapter_skip_buttons = false, -- show the chapter skip backward and forward buttons
	chapter_softrepeat = true, -- enable continuous skipping when holding down chapter skip buttons
	track_nextprev_buttons = true, -- show next/previous playlist track buttons

	volume_control = true, -- show mute button and volume slider
	volume_control_type = "linear", -- volume scale type: "linear" or "logarithmic"
	playlist_button = true, -- show playlist button: Left-click for simple playlist, Right-click for interactive playlist
	hide_empty_playlist_button = false, -- hide playlist button when no playlist exists
	gray_empty_playlist_button = false, -- gray out the playlist button when no playlist exists

	fullscreen_button = true, -- show fullscreen toggle button
	info_button = true, -- show info button
	ontop_button = true, -- show window on top button
	screenshot_button = false, -- show screenshot button

	download_button = true, -- show download button on web videos (requires yt-dlp and ffmpeg)
	download_path = "~~desktop/mpv", -- default download directory for videos (https://mpv.io/manual/master/#paths)

	loop_button = false, -- show loop
	shuffle_button = false, -- show shuffle
	speed_button = false, -- show speed control button
	speed_button_click = 1, -- speed change amount per click
	speed_button_scroll = 0.25, -- speed change amount on scroll

	loop_in_pause = true, -- enable looping by right-clicking pause

	buttons_always_active = "none", -- force buttons to always be active. can add: playlist_prev, playlist_next

	playpause_size = 28, -- icon size for the play/pause button
	midbuttons_size = 24, -- icon size for the middle buttons
	sidebuttons_size = 24, -- icon size for the side buttons

	zoom_control = true, -- show zoom controls in image viewer mode
	zoom_in_max = 4, -- maximum zoom in value
	zoom_out_min = -1, -- minimum zoom out value

	-- Colors and style
	osc_color = "#000000", -- accent color of the OSC and title bar
	window_title_color = "#FFFFFF", -- color of the title in borderless/fullscreen mode
	window_controls_color = "#FFFFFF", -- color of the window controls (close, minimize, maximize) in borderless/fullscreen mode
	windowcontrols_close_hover = "#F45C5B", -- color of close window control on hover
	windowcontrols_max_hover = "#F8BC3A", -- color of maximize window controls on hover
	windowcontrols_min_hover = "#1d3b30", -- color of minimize window controls on hover
	title_color = "#FFFFFF", -- color of the title (above seekbar)
	cache_info_color = "#FFFFFF", -- color of the cache information
	seekbarfg_color = "#FB8C00", -- color of the seekbar progress and handle
	seekbarbg_color = "#94754F", -- color of the remaining seekbar
	seekbar_cache_color = "#918F8E", -- color of the cache ranges on the seekbar
	volumebar_match_seek_color = false, -- match volume bar color with seekbar color (ignores side_buttons_color)
	time_color = "#FFFFFF", -- color of the timestamps (below seekbar)
	chapter_title_color = "#FFFFFF", -- color of the chapter title (above seekbar)
	side_buttons_color = "#FFFFFF", -- color of the side buttons (audio, subtitles, playlist, etc.)
	middle_buttons_color = "#FFFFFF", -- color of the middle buttons (skip, jump, chapter, etc.)
	playpause_color = "#FFFFFF", -- color of the play/pause button
	held_element_color = "#999999", -- color of the element when held down (pressed)
	hover_effect_color = "#FB8C00", -- color of a hovered button when hover_effect includes "color"
	thumbnail_border_color = "#111111", -- color of the border for thumbnails (with thumbfast)
	thumbnail_border_outline = "#404040", -- color of the border outline for thumbnails

	fade_alpha = 130, -- alpha of the OSC background (0 to disable)
	fade_blur_strength = 100, -- blur strength for the OSC alpha fade. caution: high values can take a lot of CPU time to render
	fade_transparency_strength = 0, -- use with "fade_blur_strength=0" to create a transparency box
	window_fade_alpha = 100, -- alpha of the window title bar (0 to disable)
	window_fade_blur_strength = 100, -- blur strength for the window title bar. caution: high values can take a lot of CPU time to render
	window_fade_transparency_strength = 0, -- use with "window_fade_blur_strength=0" to create a transparency box
	thumbnail_border = 3, -- width of the thumbnail border (for thumbfast)
	thumbnail_border_radius = 3, -- rounded corner radius for thumbnail border (0 to disable)

	-- Button hover effects
	hover_effect = "size,glow,color", -- active button hover effects: "glow", "size", "color"; can use multiple separated by commas
	hover_button_size = 115, -- relative size of a hovered button if "size" effect is active
	button_glow_amount = 5, -- glow intensity when "glow" hover effect is active
	hover_effect_for_sliders = true, -- apply size hover effect to slider handles

	-- Tooltips and hints
	tooltips_for_disabled_elements = true, -- enable tooltips for disabled buttons and elements
	tooltip_hints = true, -- enable text hints for info, loop, ontop, and screenshot buttons

	-- Progress bar settings
	seek_handle_size = 0.8, -- size ratio of the seek handle (range: 0 ~ 1)
	seekrange = true, -- show seek range overlay
	seekrangealpha = 150, -- transparency of the seek range
	livemarkers = true, -- update chapter markers on the seekbar when duration changes
	seekbarkeyframes = false, -- use keyframes when dragging the seekbar
	slider_radius = 2, -- radius of the seekbar slider (0 to disable rounded corners)

	nibbles_top = true, -- top chapter nibbles above seekbar
	nibbles_bottom = true, -- bottom chapter nibbles below seekbar
	nibbles_style = "triangle", -- chapter nibble style. "triangle", "bar", or "single-bar"

	automatickeyframemode = true, -- automatically set keyframes for the seekbar based on video length
	automatickeyframelimit = 600, -- videos longer than this (in seconds) will have keyframes on the seekbar

	persistentprogress = false, -- always show a small progress line at the bottom of the screen
	persistentprogressheight = 17, -- height of the persistent progress bar
	persistentbuffer = false, -- show buffer status on web videos in the persistent progress line

	-- Miscellaneous settings
	visibility = "auto", -- only used at init to set visibility_mode(...)
	visibility_modes = "never_auto_always", -- visibility modes to cycle through
	tick_delay = 0.03, -- minimum interval between OSC redraws (in seconds)
	tick_delay_follow_display_fps = false, -- use display FPS as the minimum redraw interval

	-- Elements Position
	-- Useful when adjusting font size or type
	title_height = 96, -- title height position above seekbar
	title_with_chapter_height = 108, -- title height position if a chapter title is below it
	chapter_title_height = 91, -- chapter title height position above seekbar
	time_codes_height = 35, -- time codes height position
	time_codes_centered_height = 57, -- time codes height position with portrait window
	tooltip_height_offset = 2, -- tooltip height position offset
	tooltip_left_offset = 5, -- if tooltip contains many characters, it is moved to the left by offset
	portrait_window_trigger = 1000, -- portrait window width trigger to move some elements
	hide_volume_bar_trigger = 1150, -- hide volume bar trigger window width
	notitle_osc_h_offset = 25, -- osc height offset if title above seekbar is disabled
	nochapter_osc_h_offset = 10, -- osc height offset if chapter title is disabled or doesn't exist
	seek_hover_tooltip_h_offset = 0, -- seek hover timecodes tooltip height position offset
	osc_height = 132, -- osc height without offsets

	-- Mouse commands
	-- customize the button function based on mouse action

	-- title above seekbar mouse actions
	title_mbtn_left_command = "script-binding stats/display-page-5",
	title_mbtn_mid_command = "show-text ${path}",
	title_mbtn_right_command = "script-binding select/select-watch-history; script-message-to modernz osc-hide",

	-- playlist button mouse actions
	playlist_mbtn_left_command = "script-binding select/menu; script-message-to modernz osc-hide",
	playlist_mbtn_right_command = "script-binding select/select-playlist; script-message-to modernz osc-hide",

	-- volume mouse actions
	vol_ctrl_mbtn_left_command = "no-osd cycle mute",
	vol_ctrl_mbtn_right_command = "script-binding select/select-audio-device; script-message-to modernz osc-hide",
	vol_ctrl_wheel_down_command = "no-osd add volume -5",
	vol_ctrl_wheel_up_command = "no-osd add volume 5",

	-- audio button mouse actions
	audio_track_mbtn_left_command = "script-binding select/select-aid; script-message-to modernz osc-hide",
	audio_track_mbtn_mid_command = "cycle audio down",
	audio_track_mbtn_right_command = "cycle audio",
	audio_track_wheel_down_command = "cycle audio",
	audio_track_wheel_up_command = "cycle audio down",

	-- subtitle button mouse actions
	sub_track_mbtn_left_command = "script-binding select/select-sid; script-message-to modernz osc-hide",
	sub_track_mbtn_mid_command = "cycle sub down",
	sub_track_mbtn_right_command = "cycle sub",
	sub_track_wheel_down_command = "cycle sub",
	sub_track_wheel_up_command = "cycle sub down",

	-- chapter skip buttons mouse actions
	chapter_prev_mbtn_left_command = "add chapter -1",
	chapter_prev_mbtn_mid_command = "show-text ${chapter-list} 3000",
	chapter_prev_mbtn_right_command = "script-binding select/select-chapter; script-message-to modernz osc-hide",

	chapter_next_mbtn_left_command = "add chapter 1",
	chapter_next_mbtn_mid_command = "show-text ${chapter-list} 3000",
	chapter_next_mbtn_right_command = "script-binding select/select-chapter; script-message-to modernz osc-hide",

	-- chapter title (below seekbar) mouse actions
	chapter_title_mbtn_left_command = "script-binding select/select-chapter; script-message-to modernz osc-hide",
	chapter_title_mbtn_right_command = "show-text ${chapter-list} 3000",

	-- playlist skip buttons mouse actions
	playlist_prev_mbtn_left_command = "playlist-prev",
	playlist_prev_mbtn_mid_command = "show-text ${playlist} 3000",
	playlist_prev_mbtn_right_command = "script-binding select/select-playlist; script-message-to modernz osc-hide",

	playlist_next_mbtn_left_command = "playlist-next",
	playlist_next_mbtn_mid_command = "show-text ${playlist} 3000",
	playlist_next_mbtn_right_command = "script-binding select/select-playlist; script-message-to modernz osc-hide",

	-- fullscreen button mouse actions
	fullscreen_mbtn_left_command = "cycle fullscreen",
	fullscreen_mbtn_right_command = "cycle window-maximized",

	-- info button mouse actions
	info_mbtn_left_command = "script-binding stats/display-page-1-toggle",

	-- screenshot button mouse actions
	screenshot_mbtn_left_command = "osd-msg screenshot subtitles",
}

mp.observe_property("osc", "bool", function(name, value)
	if value == true then
		mp.set_property("osc", "no")
	end
end)

local osc_param = { -- calculated by osc_init()
	playresy = 0, -- canvas size Y
	playresx = 0, -- canvas size X
	display_aspect = 1,
	unscaled_y = 0,
	areas = {},
	video_margins = {
		l = 0,
		r = 0,
		t = 0,
		b = 0, -- left/right/top/bottom
	},
}

local icon_theme = {
	["fluent"] = {
		iconfont = "fluent-system-icons",
		window = {
			maximize = "\238\159\171",
			unmaximize = "\238\174\150",
			minimize = "\238\175\144",
			close = "\239\141\169",
		},
		audio = "\238\175\139",
		subtitle = "\238\175\141",
		playlist = "\238\161\159",
		menu = "\238\160\170",
		volume_mute = "\238\173\138",
		volume_quiet = "\238\172\184",
		volume_low = "\238\172\189",
		volume_high = "\238\173\130",

		play = "\238\166\143",
		pause = "\238\163\140",
		replay = "\238\189\191",
		previous = "\239\152\167",
		next = "\239\149\168",
		rewind = "\238\168\158",
		forward = "\238\152\135",
		jump = {
			[5] = { "\238\171\186", "\238\171\187" },
			[10] = { "\238\171\188", "\238\172\129" },
			[30] = { "\238\172\133", "\238\172\134" },
			default = { "\238\172\138", "\238\172\138" }, -- second icon is mirrored in layout()
		},

		fullscreen = "\239\133\160",
		fullscreen_exit = "\239\133\166",
		info = "\239\146\164",
		ontop_on = "\238\165\190",
		ontop_off = "\238\166\129",
		screenshot = "\238\169\150",
		loop_off = "\239\133\178",
		loop_on = "\239\133\181",
		shuffle_off = "\238\188\188",
		shuffle_on = "\238\188\184",
		speed = "\239\160\177",
		download = "\239\133\144",
		downloading = "\239\140\174",

		zoom_in = "\238\186\142",
		zoom_out = "\238\186\143",
	},
	["material"] = {
		iconfont = "Material Design Icons",
		window = {
			maximize = "\243\176\150\175",
			unmaximize = "\243\176\150\178",
			minimize = "\243\176\150\176",
			close = "\243\176\150\173",
		},
		audio = "\243\176\151\133",
		subtitle = "\243\176\168\150",
		playlist = "\243\176\141\156", -- this icon is better suited as a generic menu button
		menu = "\243\176\149\178", -- this icon would be better suited for playlists
		volume_mute = "\243\176\184\136",
		volume_quiet = "\243\176\149\191",
		volume_low = "\243\176\150\128",
		volume_high = "\243\176\149\190",

		play = "\243\176\144\138",
		pause = "\243\176\143\164",
		replay = "\243\176\145\153",
		previous = "\243\176\146\171",
		next = "\243\176\146\172",
		rewind = "\243\176\145\159",
		forward = "\243\176\136\145",
		jump = {
			[5] = { "\243\177\135\185", "\243\177\135\184" },
			[10] = { "\243\176\180\170", "\243\176\181\177" },
			[30] = { "\243\176\182\150", "\243\176\180\134" },
			default = { "\243\176\147\151", "\243\176\147\151" }, -- first would be '\243\176\147\149' but icon is mirrored in layout()
		},

		fullscreen = "\243\176\138\147",
		fullscreen_exit = "\243\176\138\148",
		info = "\243\176\139\189",
		ontop_on = "\243\176\144\131",
		ontop_off = "\243\176\164\176",
		screenshot = "\243\176\132\128",
		loop_off = "\243\176\145\151",
		loop_on = "\243\176\145\150",
		shuffle_off = "\243\176\146\158",
		shuffle_on = "\243\176\146\157",
		speed = "\243\176\163\191",
		download = "\243\176\129\136",
		downloading = "\243\176\166\151",

		zoom_in = "\243\176\155\173",
		zoom_out = "\243\176\155\172",
	},
}

--- localization
local language = {
	["en"] = {
		idle = "Drop files or URLs here to play",
		na = "Not available",
		video = "Video",
		audio = "Audio",
		subtitle = "Subtitle",
		no_subs = "No subtitles available",
		no_audio = "No audio tracks available",
		playlist = "Playlist",
		no_playlist = "Playlist is empty",
		chapter = "Chapter",
		ontop = "Pin Window",
		ontop_disable = "Unpin Window",
		loop_enable = "Loop",
		loop_disable = "Disable Loop",
		shuffle = "Shuffle Playlist",
		unshuffle = "Unshuffle Playlist",
		speed_control = "Speed Control",
		screenshot = "Screenshot",
		stats_info = "Information",
		cache = "Cache",
		buffering = "Buffering",
		zoom_in = "Zoom In",
		zoom_out = "Zoom Out",
		download = "Download",
		download_in_progress = "Download in progress",
		downloading = "Downloading",
		downloaded = "Already downloaded",
		menu = "Menu",
	},
}

-- locale JSON file handler
function get_locale_from_json(path)
	local expand_path = mp.command_native({ "expand-path", path })

	local file_info = utils.file_info(expand_path)
	if not file_info or not file_info.is_file then
		return nil
	end

	local json_file = io.open(expand_path, "r")
	if not json_file then
		return nil
	end

	local json = json_file:read("*all")
	json_file:close()

	local json_table, parse_error = utils.parse_json(json)
	if not json_table then
		mp.msg.error("JSON parse error:" .. parse_error)
	end
	return json_table
end

-- load external locales if available
local locale_path = "~~/script-opts/modernz-locale.json"
local external = get_locale_from_json(locale_path)

if external then
	for lang, strings in pairs(external) do
		if type(strings) == "table" then
			language[lang] = strings

			-- fill in missing locales with English defaults
			for key, value in pairs(language["en"]) do
				if strings[key] == nil then
					strings[key] = value or "" -- fallback to empty string if key is missing
				end

				-- debug log to verify all keys are populated
				if strings[key] == nil then
					mp.msg.warn("Locale key '" .. key .. "' is nil in language: " .. lang)
				end
			end
		else
			mp.msg.warn("Locale data for language " .. lang .. " is not in the correct format.")
		end
	end
end

local icons
local iconfont
local function set_icon_theme()
	icons = icon_theme[user_opts.icon_theme] or icon_theme["fluent"]
	iconfont = icons.iconfont
end

local locale
local function set_osc_locale()
	locale = language[user_opts.language] or language["en"]
	local idle_ass_tags = "{\\fs24\\1c&H0&\\1c&HFFFFFF&}"
	locale.idle = idle_ass_tags .. locale.idle
end

local function contains(list, item)
	local t = type(list) == "table" and list or {}
	if type(list) ~= "table" then
		for str in string.gmatch(list, "([^,]+)") do
			t[#t + 1] = str:match("^%s*(.-)%s*$") -- trim spaces
		end
	end
	for _, v in ipairs(t) do
		if v == item then
			return true
		end
	end
	return false
end

local thumbfast = {
	width = 0,
	height = 0,
	disabled = true,
	available = false,
}

local tick_delay = 1 / 60
local audio_track_count = 0
local sub_track_count = 0
local window_control_box_width = 150
local is_december = os.date("*t").month == 12
local UNICODE_MINUS = string.char(0xe2, 0x88, 0x92) -- UTF-8 for U+2212 MINUS SIGN

local function osc_color_convert(color)
	return color:sub(6, 7) .. color:sub(4, 5) .. color:sub(2, 3)
end

local osc_styles

local function set_osc_styles()
	local playpause_size = user_opts.playpause_size or 28
	local midbuttons_size = user_opts.midbuttons_size or 24
	local sidebuttons_size = user_opts.sidebuttons_size or 24
	osc_styles = {
		osc_fade_bg = "{\\blur"
			.. user_opts.fade_blur_strength
			.. "\\bord"
			.. user_opts.fade_alpha
			.. "\\1c&H0&\\3c&H"
			.. osc_color_convert(user_opts.osc_color)
			.. "&}",
		window_fade_bg = "{\\blur"
			.. user_opts.window_fade_blur_strength
			.. "\\bord"
			.. user_opts.window_fade_alpha
			.. "\\1c&H0&\\3c&H"
			.. osc_color_convert(user_opts.osc_color)
			.. "&}",
		window_control = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.window_controls_color)
			.. "&\\3c&H0&\\fs25\\fn"
			.. iconfont
			.. "}",
		window_title = "{\\blur1\\bord0.5\\1c&H"
			.. osc_color_convert(user_opts.window_title_color)
			.. "&\\3c&H0&\\fs"
			.. user_opts.window_title_font_size
			.. "\\q2\\fn"
			.. user_opts.font
			.. "}",
		title = "{\\blur1\\bord0.5\\1c&H"
			.. osc_color_convert(user_opts.title_color)
			.. "&\\3c&H0&\\fs"
			.. user_opts.title_font_size
			.. "\\q2\\fn"
			.. user_opts.font
			.. "}",
		chapter_title = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.chapter_title_color)
			.. "&\\3c&H0&\\fs"
			.. user_opts.chapter_title_font_size
			.. "\\fn"
			.. user_opts.font
			.. "}",
		seekbar_bg = "{\\blur0\\bord0\\1c&H" .. osc_color_convert(user_opts.seekbarbg_color) .. "&}",
		seekbar_fg = "{\\blur1\\bord1\\1c&H" .. osc_color_convert(user_opts.seekbarfg_color) .. "&}",
		thumbnail = "{\\blur0\\bord1\\1c&H"
			.. osc_color_convert(user_opts.thumbnail_border_color)
			.. "&\\3c&H"
			.. osc_color_convert(user_opts.thumbnail_border_outline)
			.. "&}",
		time = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.time_color)
			.. "&\\3c&H0&\\fs"
			.. user_opts.time_font_size
			.. "\\fn"
			.. user_opts.font
			.. "}",
		cache = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.cache_info_color)
			.. "&\\3c&H0&\\fs"
			.. user_opts.cache_info_font_size
			.. "\\fn"
			.. user_opts.font
			.. "}",
		tooltip = "{\\blur1\\bord0.5\\1c&HFFFFFF&\\3c&H0&\\fs"
			.. user_opts.tooltip_font_size
			.. "\\fn"
			.. user_opts.font
			.. "}",
		volumebar_bg = "{\\blur0\\bord0\\1c&H999999&}",
		volumebar_fg = "{\\blur1\\bord1\\1c&H" .. osc_color_convert(user_opts.side_buttons_color) .. "&}",
		control_1 = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.playpause_color)
			.. "&\\3c&HFFFFFF&\\fs"
			.. playpause_size
			.. "\\fn"
			.. iconfont
			.. "}",
		control_2 = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.middle_buttons_color)
			.. "&\\3c&HFFFFFF&\\fs"
			.. midbuttons_size
			.. "\\fn"
			.. iconfont
			.. "}",
		control_2_flip = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.middle_buttons_color)
			.. "&\\3c&HFFFFFF&\\fs"
			.. midbuttons_size
			.. "\\fn"
			.. iconfont
			.. "\\fry180}",
		control_3 = "{\\blur0\\bord0\\1c&H"
			.. osc_color_convert(user_opts.side_buttons_color)
			.. "&\\3c&HFFFFFF&\\fs"
			.. sidebuttons_size
			.. "\\fn"
			.. iconfont
			.. "}",
		element_down = "{\\1c&H" .. osc_color_convert(user_opts.held_element_color) .. "&}",
		element_hover = "{" .. (contains(user_opts.hover_effect, "color") and "\\1c&H" .. osc_color_convert(
			user_opts.hover_effect_color
		) .. "&" or "") .. "\\2c&HFFFFFF&" .. (contains(user_opts.hover_effect, "size") and string.format(
			"\\fscx%s\\fscy%s",
			user_opts.hover_button_size,
			user_opts.hover_button_size
		) or "") .. "}",
	}
end

-- internal states, do not touch
local state = {
	showtime = nil, -- time of last invocation (last mouse move)
	touchtime = nil, -- time of last invocation (last touch event)
	touchpoints = {}, -- current touch points
	osc_visible = false,
	anistart = nil, -- time when the animation started
	anitype = nil, -- current type of animation
	animation = nil, -- current animation alpha
	mouse_down_counter = 0, -- used for softrepeat
	active_element = nil, -- nil = none, 0 = background, 1+ = see elements[]
	active_event_source = nil, -- the "button" that issued the current event
	tc_right_rem = not user_opts.timetotal, -- if the right timecode should display total or remaining time
	tc_ms = user_opts.timems, -- Should the timecodes display their time with milliseconds
	screen_sizeX = nil,
	screen_sizeY = nil, -- last screen-resolution, to detect resolution changes to issue reINITs
	initREQ = false, -- is a re-init request pending?
	marginsREQ = false, -- is a margins update pending?
	last_mouseX = nil,
	last_mouseY = nil, -- last mouse position, to detect significant mouse movement
	last_touchX = -1,
	last_touchY = -1, -- last touch position
	mouse_in_window = false,
	fullscreen = false,
	tick_timer = nil,
	tick_last_time = 0, -- when the last tick() was run
	hide_timer = nil,
	cache_state = nil,
	idle = false,
	enabled = true,
	input_enabled = true,
	showhide_enabled = false,
	windowcontrols_buttons = false,
	windowcontrols_title = false,
	dmx_cache = 0,
	border = true,
	maximized = false,
	osd = mp.create_osd_overlay("ass-events"),
	buffering = false,
	new_file_flag = false, -- flag to detect new file starts
	temp_visibility_mode = nil, -- store temporary visibility mode state
	chapter_list = {}, -- sorted by time
	visibility_modes = {}, -- visibility_modes to cycle through
	mute = false,
	looping = false,
	shuffled = false,
	sliderpos = 0,
	touchingprogressbar = false, -- if the mouse is touching the progress bar
	initialborder = mp.get_property("border"),
	playtime_hour_force_init = false, -- used to force request_init() once
	playtime_nohour_force_init = false, -- used to force request_init() once
	playing_and_seeking = false,
	persistent_progress_toggle = user_opts.persistentprogress,
	user_subpos = mp.get_property_number("sub-pos") or 100,
	osc_adjusted_subpos = nil,
	downloaded_once = false,
	downloading = false,
	file_size_bytes = 0,
	file_size_normalized = "Approximating size...",
	is_URL = false,
	is_image = false,
	url_path = "", -- used for yt-dlp downloading
}

local logo_lines = {
	-- White border
	"{\\c&HE5E5E5&\\p6}m 895 10 b 401 10 0 410 0 905 0 1399 401 1800 895 1800 1390 1800 1790 1399 1790 905 1790 410 1390 10 895 10 {\\p0}",
	-- Purple fill
	"{\\c&H682167&\\p6}m 925 42 b 463 42 87 418 87 880 87 1343 463 1718 925 1718 1388 1718 1763 1343 1763 880 1763 418 1388 42 925 42{\\p0}",
	-- Darker fill
	"{\\c&H430142&\\p6}m 1605 828 b 1605 1175 1324 1456 977 1456 631 1456 349 1175 349 828 349 482 631 200 977 200 1324 200 1605 482 1605 828{\\p0}",
	-- White fill
	"{\\c&HDDDBDD&\\p6}m 1296 910 b 1296 1131 1117 1310 897 1310 676 1310 497 1131 497 910 497 689 676 511 897 511 1117 511 1296 689 1296 910{\\p0}",
	-- Triangle
	"{\\c&H691F69&\\p6}m 762 1113 l 762 708 b 881 776 1000 843 1119 911 1000 978 881 1046 762 1113{\\p0}",
}

local santa_hat_lines = {
	-- Pompoms
	"{\\c&HC0C0C0&\\p6}m 500 -323 b 491 -322 481 -318 475 -311 465 -312 456 -319 446 -318 434 -314 427 -304 417 -297 410 -290 404 -282 395 -278 390 -274 387 -267 381 -265 377 -261 379 -254 384 -253 397 -244 409 -232 425 -228 437 -228 446 -218 457 -217 462 -216 466 -213 468 -209 471 -205 477 -203 482 -206 491 -211 499 -217 508 -222 532 -235 556 -249 576 -267 584 -272 584 -284 578 -290 569 -305 550 -312 533 -309 523 -310 515 -316 507 -321 505 -323 503 -323 500 -323{\\p0}",
	"{\\c&HE0E0E0&\\p6}m 315 -260 b 286 -258 259 -240 246 -215 235 -210 222 -215 211 -211 204 -188 177 -176 172 -151 170 -139 163 -128 154 -121 143 -103 141 -81 143 -60 139 -46 125 -34 129 -17 132 -1 134 16 142 30 145 56 161 80 181 96 196 114 210 133 231 144 266 153 303 138 328 115 373 79 401 28 423 -24 446 -73 465 -123 483 -174 487 -199 467 -225 442 -227 421 -232 402 -242 384 -254 364 -259 342 -250 322 -260 320 -260 317 -261 315 -260{\\p0}",
	-- Main cap
	"{\\c&H0000F0&\\p6}m 1151 -523 b 1016 -516 891 -458 769 -406 693 -369 624 -319 561 -262 526 -252 465 -235 479 -187 502 -147 551 -135 588 -111 1115 165 1379 232 1909 761 1926 800 1952 834 1987 858 2020 883 2053 912 2065 952 2088 1000 2146 962 2139 919 2162 836 2156 747 2143 662 2131 615 2116 567 2122 517 2120 410 2090 306 2089 199 2092 147 2071 99 2034 64 1987 5 1928 -41 1869 -86 1777 -157 1712 -256 1629 -337 1578 -389 1521 -436 1461 -476 1407 -509 1343 -507 1284 -515 1240 -519 1195 -521 1151 -523{\\p0}",
	-- Cap shadow
	"{\\c&H0000AA&\\p6}m 1657 248 b 1658 254 1659 261 1660 267 1669 276 1680 284 1689 293 1695 302 1700 311 1707 320 1716 325 1726 330 1735 335 1744 347 1752 360 1761 371 1753 352 1754 331 1753 311 1751 237 1751 163 1751 90 1752 64 1752 37 1767 14 1778 -3 1785 -24 1786 -45 1786 -60 1786 -77 1774 -87 1760 -96 1750 -78 1751 -65 1748 -37 1750 -8 1750 20 1734 78 1715 134 1699 192 1694 211 1689 231 1676 246 1671 251 1661 255 1657 248 m 1909 541 b 1914 542 1922 549 1917 539 1919 520 1921 502 1919 483 1918 458 1917 433 1915 407 1930 373 1942 338 1947 301 1952 270 1954 238 1951 207 1946 214 1947 229 1945 239 1939 278 1936 318 1924 356 1923 362 1913 382 1912 364 1906 301 1904 237 1891 175 1887 150 1892 126 1892 101 1892 68 1893 35 1888 2 1884 -9 1871 -20 1859 -14 1851 -6 1854 9 1854 20 1855 58 1864 95 1873 132 1883 179 1894 225 1899 273 1908 362 1910 451 1909 541{\\p0}",
	-- Brim and tip pompom
	"{\\c&HF8F8F8&\\p6}m 626 -191 b 565 -155 486 -196 428 -151 387 -115 327 -101 304 -47 273 2 267 59 249 113 219 157 217 213 215 265 217 309 260 302 285 283 373 264 465 264 555 257 608 252 655 292 709 287 759 294 816 276 863 298 903 340 972 324 1012 367 1061 394 1125 382 1167 424 1213 462 1268 482 1322 506 1385 546 1427 610 1479 662 1510 690 1534 725 1566 752 1611 796 1664 830 1703 880 1740 918 1747 986 1805 1005 1863 991 1897 932 1916 880 1914 823 1945 777 1961 725 1979 673 1957 622 1938 575 1912 534 1862 515 1836 473 1790 417 1755 351 1697 305 1658 266 1633 216 1593 176 1574 138 1539 116 1497 110 1448 101 1402 77 1371 37 1346 -16 1295 15 1254 6 1211 -27 1170 -62 1121 -86 1072 -104 1027 -128 976 -133 914 -130 851 -137 794 -162 740 -181 679 -168 626 -191 m 2051 917 b 1971 932 1929 1017 1919 1091 1912 1149 1923 1214 1970 1254 2000 1279 2027 1314 2066 1325 2139 1338 2212 1295 2254 1238 2281 1203 2287 1158 2282 1116 2292 1061 2273 1006 2229 970 2206 941 2167 938 2138 918{\\p0}",
}

--
-- Helper functions
--

local function kill_animation()
	state.anistart = nil
	state.animation = nil
	state.anitype = nil
end

local function set_osd(res_x, res_y, text, z)
	if state.osd.res_x == res_x and state.osd.res_y == res_y and state.osd.data == text then
		return
	end
	state.osd.res_x = res_x
	state.osd.res_y = res_y
	state.osd.data = text
	state.osd.z = z
	state.osd:update()
end

local function set_time_styles(timetotal_changed, timems_changed)
	if timetotal_changed then
		state.tc_right_rem = not user_opts.timetotal
	end
	if timems_changed then
		state.tc_ms = user_opts.timems
	end
end

-- scale factor for translating between real and virtual ASS coordinates
local function get_virt_scale_factor()
	local w, h = mp.get_osd_size()
	if w <= 0 or h <= 0 then
		return 0, 0
	end
	return osc_param.playresx / w, osc_param.playresy / h
end

local function recently_touched()
	if state.touchtime == nil then
		return false
	end
	return state.touchtime + 1 >= mp.get_time()
end

-- return mouse position in virtual ASS coordinates (playresx/y)
local function get_virt_mouse_pos()
	if recently_touched() then
		local sx, sy = get_virt_scale_factor()
		return state.last_touchX * sx, state.last_touchY * sy
	elseif state.mouse_in_window then
		local sx, sy = get_virt_scale_factor()
		local x, y = mp.get_mouse_pos()
		return x * sx, y * sy
	else
		return -1, -1
	end
end

local function set_virt_mouse_area(x0, y0, x1, y1, name)
	local sx, sy = get_virt_scale_factor()
	if sx == 0 or sy == 0 then
		mp.set_mouse_area(0, 0, 0, 0, name)
		return
	end
	mp.set_mouse_area(x0 / sx, y0 / sy, x1 / sx, y1 / sy, name)
end

local function scale_value(x0, x1, y0, y1, val)
	local m = (y1 - y0) / (x1 - x0)
	local b = y0 - (m * x0)
	return (m * val) + b
end

-- returns hitbox spanning coordinates (top left, bottom right corner)
-- according to alignment
local function get_hitbox_coords(x, y, an, w, h)
	local alignments = {
		[1] = function()
			return x, y - h, x + w, y
		end,
		[2] = function()
			return x - (w / 2), y - h, x + (w / 2), y
		end,
		[3] = function()
			return x - w, y - h, x, y
		end,

		[4] = function()
			return x, y - (h / 2), x + w, y + (h / 2)
		end,
		[5] = function()
			return x - (w / 2), y - (h / 2), x + (w / 2), y + (h / 2)
		end,
		[6] = function()
			return x - w, y - (h / 2), x, y + (h / 2)
		end,

		[7] = function()
			return x, y, x + w, y + h
		end,
		[8] = function()
			return x - (w / 2), y, x + (w / 2), y + h
		end,
		[9] = function()
			return x - w, y, x, y + h
		end,
	}

	return alignments[an]()
end

local function get_hitbox_coords_geo(geometry)
	return get_hitbox_coords(geometry.x, geometry.y, geometry.an, geometry.w, geometry.h)
end

local function get_element_hitbox(element)
	return element.hitbox.x1, element.hitbox.y1, element.hitbox.x2, element.hitbox.y2
end

local function mouse_hit_coords(bX1, bY1, bX2, bY2)
	local mX, mY = get_virt_mouse_pos()
	return (mX >= bX1 and mX <= bX2 and mY >= bY1 and mY <= bY2)
end

local function mouse_hit(element)
	return mouse_hit_coords(get_element_hitbox(element))
end

local function limit_range(min, max, val)
	if val > max then
		val = max
	elseif val < min then
		val = min
	end
	return val
end

-- translate value into element coordinates
local function get_slider_ele_pos_for(element, val)
	local ele_pos = scale_value(
		element.slider.min.value,
		element.slider.max.value,
		element.slider.min.ele_pos,
		element.slider.max.ele_pos,
		val
	)

	return limit_range(element.slider.min.ele_pos, element.slider.max.ele_pos, ele_pos)
end

-- translates global (mouse) coordinates to value
local function get_slider_value_at(element, glob_pos)
	if element then
		local val = scale_value(
			element.slider.min.glob_pos,
			element.slider.max.glob_pos,
			element.slider.min.value,
			element.slider.max.value,
			glob_pos
		)

		return limit_range(element.slider.min.value, element.slider.max.value, val)
	end
	-- fall back incase of loading errors
	return 0
end

-- get value at current mouse position
local function get_slider_value(element)
	return get_slider_value_at(element, get_virt_mouse_pos())
end

-- multiplies two alpha values, formular can probably be improved
local function mult_alpha(alphaA, alphaB)
	return 255 - (((1 - (alphaA / 255)) * (1 - (alphaB / 255))) * 255)
end

local function add_area(name, x1, y1, x2, y2)
	-- create area if needed
	if osc_param.areas[name] == nil then
		osc_param.areas[name] = {}
	end
	table.insert(osc_param.areas[name], { x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
end

local function ass_append_alpha(ass, alpha, modifier, inverse)
	local ar = {}

	for ai, av in pairs(alpha) do
		av = mult_alpha(av, modifier)
		if state.animation then
			local animpos = state.animation
			if inverse then
				animpos = 255 - animpos
			end
			av = mult_alpha(av, animpos)
		end
		ar[ai] = av
	end

	ass:append(string.format("{\\1a&H%X&\\2a&H%X&\\3a&H%X&\\4a&H%X&}", ar[1], ar[2], ar[3], ar[4]))
end

local function ass_draw_cir_cw(ass, x, y, r)
	ass:round_rect_cw(x - r, y - r, x + r, y + r, r)
end

local function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2)
	if hexagon then
		ass:hexagon_cw(x0, y0, x1, y1, r1, r2)
	else
		ass:round_rect_cw(x0, y0, x1, y1, r1, r2)
	end
end

local function get_hidetimeout()
	if user_opts.visibility == "always" then
		return -1 -- disable autohide
	end
	return user_opts.hidetimeout
end

local function get_touchtimeout()
	if state.touchtime == nil then
		return 0
	end
	return state.touchtime + (get_hidetimeout() / 1000) - mp.get_time()
end

local function cache_enabled()
	return state.cache_state and #state.cache_state["seekable-ranges"] > 0
end

local function update_margins()
	local margins = osc_param.video_margins

	-- Don't use margins if it's visible only temporarily.
	if
		not state.osc_visible
		or get_hidetimeout() >= 0
		or (state.fullscreen and not user_opts.showfullscreen)
		or (not state.fullscreen and not user_opts.showwindowed)
	then
		margins = { l = 0, r = 0, t = 0, b = 0 }
	end

	mp.set_property_native("user-data/osc/margins", margins)
end

local tick
-- Request that tick() is called (which typically re-renders the OSC).
-- The tick is then either executed immediately, or rate-limited if it was
-- called a small time ago.
local function request_tick()
	if state.tick_timer == nil then
		state.tick_timer = mp.add_timeout(0, tick)
	end

	if not state.tick_timer:is_enabled() then
		local now = mp.get_time()
		local timeout = tick_delay - (now - state.tick_last_time)
		if timeout < 0 then
			timeout = 0
		end
		state.tick_timer.timeout = timeout
		state.tick_timer:resume()
	end
end

local function request_init()
	state.initREQ = true
	request_tick()
end

-- Like request_init(), but also request an immediate update
local function request_init_resize()
	request_init()
	-- ensure immediate update
	state.tick_timer:kill()
	state.tick_timer.timeout = 0
	state.tick_timer:resume()
end

local function render_wipe()
	msg.trace("render_wipe()")
	state.osd.data = "" -- allows set_osd to immediately update on enable
	state.osd:remove()
end

--
-- Tracklist Management
--

-- updates the OSC internal playlists, should be run each time the track-layout changes
local function update_tracklist()
	audio_track_count, sub_track_count = 0, 0

	for _, track in pairs(mp.get_property_native("track-list")) do
		if track.type == "audio" then
			audio_track_count = audio_track_count + 1
		elseif track.type == "sub" then
			sub_track_count = sub_track_count + 1
		end
	end
end

-- convert slider_pos to logarithmic depending on volume_control user_opts
local function set_volume(slider_pos)
	local volume = slider_pos
	if user_opts.volume_control_type == "logarithmic" then
		volume = slider_pos ^ 2 / 100
	end
	return math.floor(volume)
end

-- WindowControl helpers
local function window_controls_enabled()
	local val = user_opts.window_top_bar
	if val == "auto" then
		return not (state.border and state.title_bar) or state.fullscreen
	else
		return val == "yes"
	end
end

--
-- Element Management
--
local elements = {}

local function prepare_elements()
	-- remove elements without layout or invisible
	local elements2 = {}
	for _, element in pairs(elements) do
		if element.layout ~= nil and element.visible then
			table.insert(elements2, element)
		end
	end
	elements = elements2

	local function elem_compare(a, b)
		return a.layout.layer < b.layout.layer
	end

	table.sort(elements, elem_compare)

	for _, element in pairs(elements) do
		local elem_geo = element.layout.geometry

		-- Calculate the hitbox
		local bX1, bY1, bX2, bY2 = get_hitbox_coords_geo(elem_geo)
		element.hitbox = { x1 = bX1, y1 = bY1, x2 = bX2, y2 = bY2 }

		local style_ass = assdraw.ass_new()

		-- prepare static elements
		style_ass:append("{}") -- hack to troll new_event into inserting a \n
		style_ass:new_event()
		style_ass:pos(elem_geo.x, elem_geo.y)
		style_ass:an(elem_geo.an)
		style_ass:append(element.layout.style)

		element.style_ass = style_ass

		local static_ass = assdraw.ass_new()

		if element.type == "box" then
			--draw box
			static_ass:draw_start()
			ass_draw_rr_h_cw(
				static_ass,
				0,
				0,
				elem_geo.w,
				elem_geo.h,
				element.layout.box.radius,
				element.layout.box.hexagon
			)
			static_ass:draw_stop()
		elseif element.type == "slider" then
			--draw static slider parts
			local slider_lo = element.layout.slider
			-- calculate positions of min and max points
			element.slider.min.ele_pos = user_opts.seek_handle_size > 0
					and (user_opts.seek_handle_size * elem_geo.h / 2)
				or slider_lo.border
			element.slider.max.ele_pos = elem_geo.w - element.slider.min.ele_pos
			element.slider.min.glob_pos = element.hitbox.x1 + element.slider.min.ele_pos
			element.slider.max.glob_pos = element.hitbox.x1 + element.slider.max.ele_pos

			static_ass:draw_start()
			-- a hack which prepares the whole slider area to allow center placements such like an=5
			static_ass:rect_cw(0, 0, elem_geo.w, elem_geo.h)
			static_ass:rect_ccw(0, 0, elem_geo.w, elem_geo.h)
			-- marker nibbles
			if element.slider.markerF ~= nil and slider_lo.gap > 0 then
				local markers = element.slider.markerF()
				for _, marker in pairs(markers) do
					if marker >= element.slider.min.value and marker <= element.slider.max.value then
						local s = get_slider_ele_pos_for(element, marker)
						if slider_lo.gap > 5 then -- draw triangles / bars
							local bar_h = 3 -- for "bar" and "single-bar" only
							--top
							if slider_lo.nibbles_top then
								if slider_lo.nibbles_style == "triangle" then
									static_ass:move_to(s - 3, slider_lo.gap - 5)
									static_ass:line_to(s + 3, slider_lo.gap - 5)
									static_ass:line_to(s, slider_lo.gap - 1)
								elseif slider_lo.nibbles_style == "bar" then
									static_ass:rect_cw(s - 1, slider_lo.gap - bar_h, s + 1, slider_lo.gap)
								else
									static_ass:rect_cw(s - 1, slider_lo.gap - bar_h, s + 1, elem_geo.h - slider_lo.gap)
								end
							end
							--bottom
							if slider_lo.nibbles_bottom then
								if slider_lo.nibbles_style == "triangle" then
									static_ass:move_to(s - 3, elem_geo.h - slider_lo.gap + 5)
									static_ass:line_to(s, elem_geo.h - slider_lo.gap + 1)
									static_ass:line_to(s + 3, elem_geo.h - slider_lo.gap + 5)
								elseif slider_lo.nibbles_style == "bar" then
									static_ass:rect_cw(
										s - 1,
										elem_geo.h - slider_lo.gap,
										s + 1,
										elem_geo.h - slider_lo.gap + bar_h
									)
								else
									static_ass:rect_cw(s - 1, slider_lo.gap, s + 1, elem_geo.h - slider_lo.gap + bar_h)
								end
							end
						else -- draw 2x1px nibbles
							--top
							if slider_lo.nibbles_top then
								static_ass:rect_cw(s - 1, 0, s + 1, slider_lo.gap)
							end
							--bottom
							if slider_lo.nibbles_bottom then
								static_ass:rect_cw(s - 1, elem_geo.h - slider_lo.gap, s + 1, elem_geo.h)
							end
						end
					end
				end
			end
		end

		element.static_ass = static_ass

		-- if the element is supposed to be disabled,
		-- style it accordingly and kill the eventresponders
		if not element.enabled then
			element.layout.alpha[1] = 215
			if not (element.name == "sub_track" or element.name == "audio_track" or element.name == "tog_playlist") then -- keep these to display tooltips
				element.eventresponder = nil
			end
		end

		-- gray out the element if it is toggled off
		if element.off then
			element.layout.alpha[1] = 100
		end
	end
end

--
-- Element Rendering
--

-- returns nil or a chapter element from the native property chapter-list
local function get_chapter(possec)
	local cl = state.chapter_list -- sorted, get latest before possec, if any

	for n = #cl, 1, -1 do
		if possec >= cl[n].time then
			return cl[n]
		end
	end
end

-- Draws a handle on the seekbar according to user_opts
-- Returns handle position and radius
local function draw_seekbar_handle(element, elem_ass, override_alpha)
	local pos = element.slider.posF()
	if not pos then
		return 0, 0
	end
	local display_handle = user_opts.seek_handle_size > 0
	local elem_geo = element.layout.geometry
	local rh = display_handle and (user_opts.seek_handle_size * elem_geo.h / 2) or 0 -- handle radius
	local xp = get_slider_ele_pos_for(element, pos) -- handle position
	local handle_hovered = mouse_hit_coords(
		element.hitbox.x1 + xp - rh,
		element.hitbox.y1 + elem_geo.h / 2 - rh,
		element.hitbox.x1 + xp + rh,
		element.hitbox.y1 + elem_geo.h / 2 + rh
	) and element.enabled

	if display_handle then
		-- Apply size hover_effect only if hovering over the handle
		if handle_hovered and user_opts.hover_effect_for_sliders then
			if contains(user_opts.hover_effect, "size") then
				rh = rh * (user_opts.hover_button_size / 100)
			end
		end

		ass_draw_cir_cw(elem_ass, xp, elem_geo.h / 2, rh)

		if user_opts.hover_effect_for_sliders then
			elem_ass:draw_stop()
			elem_ass:merge(element.style_ass)
			ass_append_alpha(elem_ass, element.layout.alpha, override_alpha or 0)
			elem_ass:merge(element.static_ass)
		end

		return xp, rh
	end
	return xp, 0
end

-- Draws seekbar ranges according to user_opts
local function draw_seekbar_ranges(element, elem_ass, xp, rh, override_alpha)
	local handle = xp and rh
	xp = xp or 0
	rh = rh or 0
	local slider_lo = element.layout.slider
	local elem_geo = element.layout.geometry
	local seekRanges = element.slider.seekRangesF()
	if not seekRanges then
		return
	end
	elem_ass:draw_stop()
	elem_ass:merge(element.style_ass)
	ass_append_alpha(elem_ass, element.layout.alpha, override_alpha or user_opts.seekrangealpha)
	elem_ass:append("{\\1cH&" .. osc_color_convert(user_opts.seekbar_cache_color) .. "&}")
	elem_ass:merge(element.static_ass)

	local slider_lo = element.layout.slider
	local radius = slider_lo.radius or 0

	for _, range in pairs(seekRanges) do
		local pstart = math.max(0, get_slider_ele_pos_for(element, range["start"]) - slider_lo.gap)
		local pend = math.min(elem_geo.w, get_slider_ele_pos_for(element, range["end"]) + slider_lo.gap)

		if handle and (pstart < xp + rh and pend > xp - rh) then
			if pstart < xp - rh then
				if radius > 0 then
					elem_ass:round_rect_cw(pstart, slider_lo.gap, xp - rh, elem_geo.h - slider_lo.gap, radius)
				else
					elem_ass:rect_cw(pstart, slider_lo.gap, xp - rh, elem_geo.h - slider_lo.gap)
				end
			end
			pstart = xp + rh
		end

		if pend > pstart then
			if radius > 0 then
				elem_ass:round_rect_cw(pstart, slider_lo.gap, pend, elem_geo.h - slider_lo.gap, radius)
			else
				elem_ass:rect_cw(pstart, slider_lo.gap, pend, elem_geo.h - slider_lo.gap)
			end
		end
	end
end

-- Draw seekbar progress more accurately
local function draw_seekbar_progress(element, elem_ass)
	local pos = element.slider.posF()
	if not pos then
		return
	end
	local xp = get_slider_ele_pos_for(element, pos)
	local slider_lo = element.layout.slider
	local elem_geo = element.layout.geometry
	local radius = slider_lo.radius or 0
	if radius > 0 then
		elem_ass:round_rect_cw(0, slider_lo.gap, xp, elem_geo.h - slider_lo.gap, radius)
	else
		elem_ass:rect_cw(0, slider_lo.gap, xp, elem_geo.h - slider_lo.gap)
	end
end

local function render_elements(master_ass)
	-- when the slider is dragged or hovered and we have a target chapter name
	-- then we use it instead of the normal title. we calculate it before the
	-- render iterations because the title may be rendered before the slider.
	state.forced_title = nil

	-- disable displaying chapter name in title when thumbfast is available
	-- because thumbfast will render it above the thumbnail instead
	if thumbfast.disabled then
		local se, ae = state.slider_element, elements[state.active_element]
		if user_opts.chapter_fmt ~= "no" and state.touchingprogressbar then
			local dur = mp.get_property_number("duration", 0)
			if dur > 0 then
				local ch = get_chapter(state.sliderpos * dur / 100)
				if ch and ch.title and ch.title ~= "" then
					state.forced_title = string.format(user_opts.chapter_fmt, ch.title)
				end
			end
		end
	end

	state.touchingprogressbar = false

	for n = 1, #elements do
		local element = elements[n]
		local style_ass = assdraw.ass_new()
		style_ass:merge(element.style_ass)
		ass_append_alpha(style_ass, element.layout.alpha, 0)

		if element.eventresponder and (state.active_element == n) then
			-- run render event functions
			if element.eventresponder.render ~= nil then
				element.eventresponder.render(element)
			end
			if mouse_hit(element) then
				-- mouse down styling
				if element.styledown then
					style_ass:append(osc_styles.element_down)
				end
				if element.softrepeat and state.mouse_down_counter >= 15 and state.mouse_down_counter % 5 == 0 then
					element.eventresponder[state.active_event_source .. "_down"](element)
				end
				state.mouse_down_counter = state.mouse_down_counter + 1
			end
		end

		local elem_ass = assdraw.ass_new()
		elem_ass:merge(style_ass)

		if element.type ~= "button" then
			elem_ass:merge(element.static_ass)
		end

		if element.type == "slider" then
			if element.name ~= "persistentseekbar" then
				local slider_lo = element.layout.slider
				local elem_geo = element.layout.geometry
				local s_min = element.slider.min.value
				local s_max = element.slider.max.value

				local xp, rh = draw_seekbar_handle(element, elem_ass) -- handle posistion, handle radius
				draw_seekbar_progress(element, elem_ass)
				draw_seekbar_ranges(element, elem_ass, xp, rh)

				elem_ass:draw_stop()

				-- add tooltip
				if element.slider.tooltipF ~= nil and element.enabled then
					local force_seek_tooltip = user_opts.force_seek_tooltip
						and element.name == "seekbar"
						and element.eventresponder["mbtn_left_down"]
						and element.state.mbtnleft
						and state.mouse_down_counter > 0
						and state.playing_and_seeking
					if mouse_hit(element) or force_seek_tooltip then
						local sliderpos = get_slider_value(element)
						local tooltiplabel = element.slider.tooltipF(sliderpos)
						local an = slider_lo.tooltip_an
						local ty
						if an == 2 then
							ty = element.hitbox.y1 - user_opts.seek_hover_tooltip_h_offset
						else
							ty = element.hitbox.y1 + elem_geo.h / 2 - user_opts.seek_hover_tooltip_h_offset
						end

						local tx = get_virt_mouse_pos()
						if slider_lo.adjust_tooltip then
							if an == 2 then
								if sliderpos < (s_min + 3) then
									an = an - 1
								elseif sliderpos > (s_max - 3) then
									an = an + 1
								end
							elseif sliderpos > (s_max + s_min) / 2 then
								an = an + 1
								tx = tx - 5
							else
								an = an - 1
								tx = tx + 10
							end
						end

						if element.name == "seekbar" then
							state.sliderpos = sliderpos
						end

						-- chapter title tooltip on show_title=false and no thumbfast
						-- add hovered chapter title above time code tooltip on seekbar hover
						if thumbfast.disabled and not user_opts.show_title and not user_opts.show_chapter_title then
							local osd_w = mp.get_property_number("osd-width")
							local r_w, r_h = get_virt_scale_factor()
							if osd_w then
								if user_opts.chapter_fmt ~= "no" and state.touchingprogressbar then
									local dur = mp.get_property_number("duration", 0)
									if dur > 0 then
										local ch = get_chapter(state.sliderpos * dur / 100)
										if ch and ch.title and ch.title ~= "" then
											local titleX = math.min(osd_w - (50 / r_w), math.max((60 / r_w), tx / r_w))
											local titleY = ty - (user_opts.time_font_size * 1.3)

											elem_ass:new_event()
											elem_ass:pos(titleX * r_w, titleY)
											elem_ass:an(2)
											elem_ass:append(slider_lo.tooltip_style)
											ass_append_alpha(elem_ass, slider_lo.alpha, 0)
											elem_ass:append(string.format(user_opts.chapter_fmt, ch.title))
										end
									end
								end
							end
						-- thumbfast
						elseif element.thumbnailable and not thumbfast.disabled then
							local osd_w = mp.get_property_number("osd-width")
							local r_w, r_h = get_virt_scale_factor()

							if osd_w then
								local hover_sec = 0
								if mp.get_property_number("duration") then
									hover_sec = mp.get_property_number("duration") * sliderpos / 100
								end
								local thumbPad = user_opts.thumbnail_border
								local thumbMarginX = 18 / r_w
								local thumbMarginY = user_opts.time_font_size + thumbPad + 2 / r_h
								local thumbX = math.min(
									osd_w - thumbfast.width - thumbMarginX,
									math.max(thumbMarginX, tx / r_w - thumbfast.width / 2)
								)
								local thumbY = (ty - thumbMarginY) / r_h - thumbfast.height

								thumbX = math.floor(thumbX + 0.5)
								thumbY = math.floor(thumbY + 0.5)

								if state.anitype == nil then
									elem_ass:new_event()
									elem_ass:append("{\\rDefault}")
									elem_ass:pos(thumbX * r_w, ty - thumbMarginY - thumbfast.height * r_h)
									elem_ass:an(7)
									elem_ass:append(osc_styles.thumbnail)
									elem_ass:draw_start()
									if user_opts.thumbnail_border_radius and user_opts.thumbnail_border_radius > 0 then
										elem_ass:round_rect_cw(
											-thumbPad * r_w,
											-thumbPad * r_h,
											(thumbfast.width + thumbPad) * r_w,
											(thumbfast.height + thumbPad) * r_h,
											user_opts.thumbnail_border_radius
										)
									else
										elem_ass:rect_cw(
											-thumbPad * r_w,
											-thumbPad * r_h,
											(thumbfast.width + thumbPad) * r_w,
											(thumbfast.height + thumbPad) * r_h
										)
									end
									elem_ass:draw_stop()

									-- force tooltip to be centered on the thumb, even at far left/right of screen
									tx = (thumbX + thumbfast.width / 2) * r_w
									an = 2

									mp.commandv("script-message-to", "thumbfast", "thumb", hover_sec, thumbX, thumbY)
								end

								-- chapter title tooltip
								local se, ae = state.slider_element, elements[state.active_element]
								if user_opts.chapter_fmt ~= "no" and state.touchingprogressbar then
									local dur = mp.get_property_number("duration", 0)
									if dur > 0 then
										local ch = get_chapter(state.sliderpos * dur / 100)
										if ch and ch.title and ch.title ~= "" then
											elem_ass:new_event()
											elem_ass:pos(
												(thumbX + thumbfast.width / 2) * r_w,
												thumbY * r_h - user_opts.time_font_size / 2
											)
											elem_ass:an(an)
											elem_ass:append(slider_lo.tooltip_style)
											ass_append_alpha(elem_ass, slider_lo.alpha, 0)
											elem_ass:append(string.format(user_opts.chapter_fmt, ch.title))
										end
									end
								end
							end
						end

						-- tooltip label
						elem_ass:new_event()
						elem_ass:pos(tx, ty)
						elem_ass:an(an)
						elem_ass:append(slider_lo.tooltip_style)
						ass_append_alpha(elem_ass, slider_lo.alpha, 0)
						elem_ass:append(tooltiplabel)
					elseif element.thumbnailable and thumbfast.available then
						mp.commandv("script-message-to", "thumbfast", "clear")
					end
				end
			end
		elseif element.type == "button" then
			local buttontext
			if type(element.content) == "function" then
				buttontext = element.content() -- function objects
			elseif element.content ~= nil then
				buttontext = element.content -- text objects
			end

			local maxchars = element.layout.button.maxchars
			if maxchars ~= nil and #buttontext > maxchars then
				local max_ratio = 1.25 -- up to 25% more chars while shrinking
				local limit = math.max(0, math.floor(maxchars * max_ratio) - 3)
				if #buttontext > limit then
					while #buttontext > limit do
						buttontext = buttontext:gsub(".[\128-\191]*$", "")
					end
					buttontext = buttontext .. "..."
				end
				buttontext = string.format("{\\fscx%f}", (maxchars / #buttontext) * 100) .. buttontext
			end

			-- add hover effects
			local button_lo = element.layout.button
			local is_clickable = element.eventresponder
				and (element.eventresponder["mbtn_left_down"] ~= nil or element.eventresponder["mbtn_left_up"] ~= nil)
			local hovered = mouse_hit(element) and is_clickable and element.enabled and state.mouse_down_counter == 0
			local hoverstyle = button_lo.hoverstyle
			if hovered and (contains(user_opts.hover_effect, "size") or contains(user_opts.hover_effect, "color")) then
				-- remove font scale tags for these elements, it looks out of place
				if
					element.name == "title"
					or element.name == "time_codes"
					or element.name == "chapter_title"
					or element.name == "cache_info"
				then
					hoverstyle = hoverstyle:gsub("\\fscx%d+\\fscy%d+", "")
				end
				elem_ass:append(hoverstyle .. buttontext)
			else
				elem_ass:append(buttontext)
			end

			-- apply blur effect if "glow" is in hover effects
			if hovered and contains(user_opts.hover_effect, "glow") then
				local shadow_ass = assdraw.ass_new()
				shadow_ass:merge(style_ass)
				shadow_ass:append("{\\blur" .. user_opts.button_glow_amount .. "}" .. hoverstyle .. buttontext)
				elem_ass:merge(shadow_ass)
			end

			-- add tooltip for button elements
			if element.tooltipF ~= nil and (user_opts.tooltips_for_disabled_elements or element.enabled) then
				if mouse_hit(element) then
					local tooltiplabel = element.tooltipF
					local an = 1
					local ty = element.hitbox.y1 - user_opts.tooltip_height_offset
					local tx = get_virt_mouse_pos()

					if ty < osc_param.playresy / 2 then
						ty = element.hitbox.y2 - user_opts.tooltip_height_offset
						an = 7
					end

					-- tooltip label
					if element.enabled then
						if type(element.tooltipF) == "function" then
							tooltiplabel = element.tooltipF()
						else
							tooltiplabel = element.tooltipF
						end
					else
						tooltiplabel = element.nothingavailable
					end

					if tx > osc_param.playresx / 2 then -- move tooltip to left side of mouse cursor
						tx = tx - string.len(tooltiplabel) * user_opts.tooltip_left_offset
					end

					elem_ass:new_event()
					elem_ass:append("{\\rDefault}")
					elem_ass:pos(tx, ty)
					elem_ass:an(an)
					elem_ass:append(element.tooltip_style)
					elem_ass:append(tooltiplabel)
				end
			end
		end

		master_ass:merge(elem_ass)
	end
end

local function render_persistentprogressbar(master_ass)
	for n = 1, #elements do
		local element = elements[n]
		if element.name == "persistentseekbar" then
			local style_ass = assdraw.ass_new()
			style_ass:merge(element.style_ass)
			if state.animation or not state.osc_visible then
				ass_append_alpha(style_ass, element.layout.alpha, 0, true)

				local elem_ass = assdraw.ass_new()
				elem_ass:merge(style_ass)
				if element.type ~= "button" then
					elem_ass:merge(element.static_ass)
				end

				-- draw pos marker
				draw_seekbar_progress(element, elem_ass)

				if user_opts.persistentbuffer then
					draw_seekbar_ranges(element, elem_ass, nil, nil)
				end

				elem_ass:draw_stop()
				master_ass:merge(elem_ass)
			end
		end
	end
end

--
-- Initialisation and Layout
--
local function is_url(s)
	if not s then
		user_opts.download_button = false
		return false
	end

	local url_pattern = "^[%w]+://[%w%.%-_]+%.[%a]+[-%w%.%-%_/?&=]*"
	return string.match(s, url_pattern) ~= nil
end

local function exec_filesize(args)
	for i = #args, 1, -1 do
		if args[i] == nil or args[i] == "" then
			table.remove(args, i)
		end
	end

	mp.command_native_async({
		name = "subprocess",
		args = args,
		capture_stdout = true,
		capture_stderr = true,
	}, function(res, val)
		local fileSizeString = val.stdout
		state.file_size_bytes = tonumber(fileSizeString)

		if state.file_size_bytes then
			state.file_size_normalized = utils.format_bytes_humanized(state.file_size_bytes)
			msg.info("Download size: " .. state.file_size_normalized)
		else
			local fs_prop = mp.get_property_osd("file-size")

			if fs_prop and fs_prop ~= "" then
				state.file_size_normalized = fs_prop
				msg.info("Download size: " .. fs_prop)
			else
				state.file_size_normalized = "Unknown"
				msg.info("Unable to retrieve file size.")
			end
		end

		request_tick()
	end)
end

local function download_done(success, result, error)
	if success then
		local download_path = mp.command_native({ "expand-path", user_opts.download_path })
		mp.commandv("show-text", "Download saved to " .. download_path)
		state.downloaded_once = true
		msg.info("Download completed")
	else
		mp.commandv("show-text", "Download failed - " .. (error or "Unknown error"))
		msg.info("Download failed")
	end
	state.downloading = false
end

local function exec(args, callback)
	for i = #args, 1, -1 do
		if args[i] == nil or args[i] == "" then
			table.remove(args, i)
		end
	end

	msg.info("Executing command: " .. table.concat(args, " "))

	local ret = mp.command_native_async({
		name = "subprocess",
		args = args,
		capture_stdout = true,
		capture_stderr = true,
	}, callback)

	return ret and ret.status or nil
end

local function check_path_url()
	state.is_URL = false
	state.downloading = false

	local path = mp.get_property("path")
	if not path then
		return nil
	end

	if string.find(path, "https://") then
		path = string.gsub(path, "ytdl://", "") -- Remove "ytdl://" prefix
	else
		path = string.gsub(path, "ytdl://", "https://") -- Replace "ytdl://" with "https://"
	end

	-- use current or default ytdl-format
	local mpv_ytdl = mp.get_property("file-local-options/ytdl-format") or mp.get_property("ytdl-format") or ""
	local ytdl_format = (mpv_ytdl and mpv_ytdl ~= "") and "-f " .. mpv_ytdl or "-f " .. "bestvideo+bestaudio/best"

	if is_url(path) then
		state.is_URL = true
		state.url_path = path
		msg.info("URL detected.")

		if user_opts.download_button then
			msg.info("Fetching file size...")
			local command = {
				"yt-dlp",
				state.is_image and "" or ytdl_format,
				"--no-download",
				"-O",
				"%(filesize,filesize_approx)s", -- Fetch file size or approximate size
				path,
			}
			exec_filesize(command)
		end
	end
end

local function new_element(name, type)
	elements[name] = {}
	elements[name].type = type
	elements[name].name = name

	-- add default stuff
	elements[name].eventresponder = {}
	elements[name].visible = true
	elements[name].enabled = true
	elements[name].softrepeat = false
	elements[name].styledown = (type == "button")
	elements[name].state = {}

	if type == "slider" then
		elements[name].slider = { min = { value = 0 }, max = { value = 100 } }
		elements[name].thumbnailable = false
	end

	return elements[name]
end

local function add_layout(name)
	if elements[name] ~= nil then
		-- new layout
		elements[name].layout = {}

		-- set layout defaults
		elements[name].layout.layer = 50
		elements[name].layout.alpha = { [1] = 0, [2] = 255, [3] = 255, [4] = 255 }

		if elements[name].type == "button" then
			elements[name].layout.button = {
				maxchars = nil,
				hoverstyle = osc_styles.element_hover,
			}
		elseif elements[name].type == "slider" then
			-- slider defaults
			elements[name].layout.slider = {
				border = 1,
				gap = 1,
				radius = 0,
				nibbles_top = user_opts.nibbles_top,
				nibbles_bottom = user_opts.nibbles_bottom,
				nibbles_style = user_opts.nibbles_style,
				adjust_tooltip = true,
				tooltip_style = "",
				tooltip_an = 2,
				alpha = { [1] = 0, [2] = 255, [3] = 88, [4] = 255 },
				hoverstyle = osc_styles.element_hover:gsub("\\fscx%d+\\fscy%d+", ""), -- font scales messes with handle positions in werid ways
			}
		elseif elements[name].type == "box" then
			elements[name].layout.box = { radius = 0, hexagon = false }
		end

		return elements[name].layout
	else
		msg.error("Can't add_layout to element '" .. name .. "', doesn't exist.")
	end
end

-- Window Controls
local function window_controls()
	local wc_geo = {
		x = 0,
		y = 50,
		an = 1,
		w = osc_param.playresx,
		h = 50,
	}

	local lo
	local controlbox_w = window_control_box_width
	local titlebox_w = wc_geo.w - controlbox_w
	local controlbox_left = wc_geo.w - controlbox_w
	local titlebox_left = wc_geo.x
	local titlebox_right = wc_geo.w - controlbox_w
	local button_y = wc_geo.y - (wc_geo.h / 2)
	local first_geo = { x = controlbox_left + 25, y = button_y, an = 5, w = 50, h = wc_geo.h }
	local second_geo = { x = controlbox_left + 75, y = button_y, an = 5, w = 49, h = wc_geo.h }
	local third_geo = { x = controlbox_left + 125, y = button_y, an = 5, w = 50, h = wc_geo.h }

	-- Window controls
	if user_opts.window_controls then
		-- Close: 🗙
		lo = add_layout("close")
		lo.geometry = third_geo
		lo.style = osc_styles.window_control
		lo.button.hoverstyle = "{\\c&H"
			.. osc_color_convert(user_opts.windowcontrols_close_hover)
			.. "&"
			.. (contains(user_opts.hover_effect, "size") and string.format(
				"\\fscx%s\\fscy%s",
				user_opts.hover_button_size,
				user_opts.hover_button_size
			) or "")
			.. "}"

		-- Minimize: 🗕
		lo = add_layout("minimize")
		lo.geometry = first_geo
		lo.style = osc_styles.window_control
		lo.button.hoverstyle = "{\\c&H"
			.. osc_color_convert(user_opts.windowcontrols_min_hover)
			.. "&"
			.. (contains(user_opts.hover_effect, "size") and string.format(
				"\\fscx%s\\fscy%s",
				user_opts.hover_button_size,
				user_opts.hover_button_size
			) or "")
			.. "}"

		-- Maximize: 🗖 /🗗
		lo = add_layout("maximize")
		lo.geometry = second_geo
		lo.style = osc_styles.window_control
		lo.button.hoverstyle = "{\\c&H"
			.. osc_color_convert(user_opts.windowcontrols_max_hover)
			.. "&"
			.. (contains(user_opts.hover_effect, "size") and string.format(
				"\\fscx%s\\fscy%s",
				user_opts.hover_button_size,
				user_opts.hover_button_size
			) or "")
			.. "}"

		add_area("window-controls", get_hitbox_coords(controlbox_left, wc_geo.y, wc_geo.an, controlbox_w, wc_geo.h))
	end

	-- Window Title
	if user_opts.show_window_title then
		lo = add_layout("windowtitle")
		lo.geometry = { x = 20, y = button_y + 14, an = 1, w = osc_param.playresx - 50, h = wc_geo.h }
		lo.style = string.format(
			"%s{\\clip(%f,%f,%f,%f)}",
			osc_styles.window_title,
			titlebox_left,
			wc_geo.y - wc_geo.h,
			titlebox_right,
			wc_geo.y + wc_geo.h
		)

		add_area("window-controls-title", titlebox_left, 0, titlebox_right, wc_geo.h)
	end
end

--
-- ModernZ Layout
--

local layouts = {}

-- Default layout
layouts["modern"] = function()
	local no_title = (
		(user_opts.title_mbtn_left_command == "" or user_opts.title_mbtn_left_command == "ignore")
		and (user_opts.title_mbtn_right_command == "" or user_opts.title_mbtn_right_command == "ignore")
	) or not user_opts.show_title

	local no_chapter = (
		(user_opts.chapter_title_mbtn_left_command == "" or user_opts.chapter_title_mbtn_left_command == "ignore")
		and (user_opts.chapter_title_mbtn_right_command == "" or user_opts.chapter_title_mbtn_right_command == "ignore")
	) or not user_opts.show_chapter_title

	local chapter_index = user_opts.show_chapter_title and mp.get_property_number("chapter", -1) >= 0
	local osc_height_offset = (no_title and user_opts.notitle_osc_h_offset or 0)
		+ ((no_chapter or not chapter_index) and user_opts.nochapter_osc_h_offset or 0)

	local osc_geo = {
		w = osc_param.playresx,
		h = user_opts.osc_height - osc_height_offset,
	}

	-- update bottom margin
	osc_param.video_margins.b = math.max(user_opts.osc_height, user_opts.fade_alpha) / osc_param.playresy

	-- origin of the controllers, left/bottom corner
	local posX = 0
	local posY = osc_param.playresy

	osc_param.areas = {} -- delete areas

	-- area for active mouse input
	add_area("input", get_hitbox_coords(posX, posY, 1, osc_geo.w, osc_geo.h))

	-- area for show/hide
	add_area("showhide", 0, 0, osc_param.playresx, osc_param.playresy)

	-- fetch values
	local osc_w, osc_h = osc_geo.w, osc_geo.h

	-- Controller Background
	local lo, geo

	new_element("osc_fade_bg", "box")
	lo = add_layout("osc_fade_bg")
	lo.geometry = { x = posX, y = posY, an = 7, w = osc_w, h = 1 }
	lo.style = osc_styles.osc_fade_bg
	lo.layer = 10
	lo.alpha[3] = user_opts.fade_transparency_strength

	local top_titlebar = window_controls_enabled() and (user_opts.show_window_title or user_opts.window_controls)

	-- Window bar alpha
	if
		((user_opts.window_top_bar == "yes" or not (state.border and state.title_bar)) or state.fullscreen)
		and top_titlebar
	then
		new_element("window_bar_alpha_bg", "box")
		lo = add_layout("window_bar_alpha_bg")
		lo.geometry = { x = posX, y = -100, an = 7, w = osc_w, h = -1 }
		lo.style = osc_styles.window_fade_bg
		lo.layer = 10
		lo.alpha[3] = user_opts.window_fade_transparency_strength
	end

	-- Alignment
	local refX = osc_w / 2
	local refY = posY

	-- Seekbar
	new_element("seekbarbg", "box")
	lo = add_layout("seekbarbg")
	local seekbar_bg_h = 4
	lo.geometry = { x = refX, y = refY - 72, an = 5, w = osc_geo.w - 50, h = seekbar_bg_h }
	lo.layer = 13
	lo.style = osc_styles.seekbar_bg
	lo.box.radius = user_opts.slider_radius
	lo.alpha[1] = 128
	lo.alpha[3] = 128

	lo = add_layout("seekbar")
	local seekbar_h = 18
	lo.geometry = { x = refX, y = refY - 72, an = 5, w = osc_geo.w - 50, h = seekbar_h }
	lo.layer = 51
	lo.style = osc_styles.seekbar_fg
	lo.slider.gap = (seekbar_h - seekbar_bg_h) / 2.0
	lo.slider.radius = user_opts.slider_radius
	lo.slider.tooltip_style = osc_styles.tooltip
	lo.slider.tooltip_an = 2

	if user_opts.persistentprogress or state.persistent_progress_toggle then
		lo = add_layout("persistentseekbar")
		lo.geometry = { x = refX, y = refY, an = 5, w = osc_geo.w, h = user_opts.persistentprogressheight }
		lo.style = osc_styles.seekbar_fg
		lo.slider.gap = (seekbar_h - seekbar_bg_h) / 2.0
		lo.slider.tooltip_an = 0
	end

	local audio_track = audio_track_count > 0
	local subtitle_track = sub_track_count > 0
	local jump_buttons = user_opts.jump_buttons
	local chapter_skip_buttons = user_opts.chapter_skip_buttons
	local track_nextprev_buttons = user_opts.track_nextprev_buttons
	local fullscreen_button = user_opts.fullscreen_button
	local info_button = user_opts.info_button
	local ontop_button = user_opts.ontop_button
	local screenshot_button = user_opts.screenshot_button
	local loop_button = user_opts.loop_button
	local shuffle_button = user_opts.shuffle_button
	local speed_button = user_opts.speed_button
	local download_button = user_opts.download_button and state.is_URL
	local playlist_button = user_opts.playlist_button
		and (not user_opts.hide_empty_playlist_button or mp.get_property_number("playlist-count", 0) > 1)

	local offset = jump_buttons and 60 or 0
	local outeroffset = (chapter_skip_buttons and 0 or 100) + (jump_buttons and 0 or 100)

	-- OSC title
	geo = {
		x = 25,
		y = refY - (chapter_index and user_opts.title_with_chapter_height or user_opts.title_height),
		an = 1,
		w = osc_geo.w - 50 - (loop_button and 45 or 0) - (speed_button and 45 or 0),
		h = user_opts.title_font_size,
	}
	lo = add_layout("title")
	lo.geometry = geo
	lo.style = string.format("%s{\\clip(0,%f,%f,%f)}", osc_styles.title, geo.y - geo.h, geo.x + geo.w, geo.y + geo.h)
	lo.alpha[3] = 0

	-- Chapter title (above seekbar)
	if user_opts.show_chapter_title then
		lo = add_layout("chapter_title")
		lo.geometry = {
			x = 26,
			y = refY - user_opts.chapter_title_height,
			an = 1,
			w = osc_geo.w / 2,
			h = user_opts.chapter_title_font_size,
		}
		lo.style = string.format(
			"%s{\\clip(0,%f,%f,%f)}",
			osc_styles.chapter_title,
			geo.y - geo.h,
			geo.x + geo.w,
			geo.y + geo.h
		)
	end

	-- buttons
	if track_nextprev_buttons then
		lo = add_layout("playlist_prev")
		lo.geometry =
			{ x = refX - (60 + (chapter_skip_buttons and 60 or 0)) - offset, y = refY - 35, an = 5, w = 30, h = 24 }
		lo.style = osc_styles.control_2
	end

	if chapter_skip_buttons then
		lo = add_layout("chapter_backward")
		lo.geometry = { x = refX - 60 - offset, y = refY - 35, an = 5, w = 30, h = 24 }
		lo.style = osc_styles.control_2
	end

	if jump_buttons then
		lo = add_layout("jump_backward")
		lo.geometry = { x = refX - 60, y = refY - 35, an = 5, w = 30, h = 24 }
		lo.style = (user_opts.jump_icon_number and icons.jump[user_opts.jump_amount] ~= nil) and osc_styles.control_2
			or osc_styles.control_2_flip
	end

	lo = add_layout("play_pause")
	lo.geometry = { x = refX, y = refY - 35, an = 5, w = 45, h = 28 }
	lo.style = osc_styles.control_1

	if jump_buttons then
		lo = add_layout("jump_forward")
		lo.geometry = { x = refX + 60, y = refY - 35, an = 5, w = 30, h = 24 }
		lo.style = osc_styles.control_2
	end

	if chapter_skip_buttons then
		lo = add_layout("chapter_forward")
		lo.geometry = { x = refX + 60 + offset, y = refY - 35, an = 5, w = 30, h = 24 }
		lo.style = osc_styles.control_2
	end

	if track_nextprev_buttons then
		lo = add_layout("playlist_next")
		lo.geometry =
			{ x = refX + (60 + (chapter_skip_buttons and 60 or 0)) + offset, y = refY - 35, an = 5, w = 30, h = 24 }
		lo.style = osc_styles.control_2
	end

	local start_x = 37

	-- Playlist
	if playlist_button then
		lo = add_layout("tog_playlist")
		lo.geometry = { x = start_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 600 - outeroffset)
		start_x = start_x + 45
	end

	-- Audio
	if audio_track then
		lo = add_layout("audio_track")
		lo.geometry = { x = start_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 500 - outeroffset)
		start_x = start_x + 45
	end

	-- Subtitle
	if subtitle_track then
		lo = add_layout("sub_track")
		lo.geometry = { x = start_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 600 - outeroffset)
		start_x = start_x + 45
	end

	if audio_track then
		-- Volume
		lo = add_layout("vol_ctrl")
		lo.geometry = { x = start_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 600 - outeroffset)
		start_x = start_x + 28

		-- Volumebar
		lo = new_element("volumebarbg", "box")
		lo.visible = (osc_param.playresx >= 1150 - outeroffset) and user_opts.volume_control
		lo = add_layout("volumebarbg")
		lo.geometry = { x = start_x, y = refY - 35, an = 4, w = 55, h = 4 }
		lo.layer = 13
		lo.alpha[1] = 128
		lo.style = user_opts.volumebar_match_seek_color and osc_styles.seekbar_bg or osc_styles.volumebar_bg
		lo.box.radius = user_opts.slider_radius

		lo = add_layout("volumebar")
		lo.geometry = { x = start_x, y = refY - 35, an = 4, w = 55, h = 10 }
		lo.style = user_opts.volumebar_match_seek_color and osc_styles.seekbar_fg or osc_styles.volumebar_fg
		lo.slider.gap = 3
		lo.slider.radius = user_opts.slider_radius
		lo.slider.tooltip_style = osc_styles.tooltip
		lo.slider.tooltip_an = 2
		start_x = start_x + 75
	end

	-- Time codes
	local remsec = mp.get_property_number("playtime-remaining", 0)
	local dur = mp.get_property_number("duration", 0)
	local show_hours = mp.get_property_number("playback-time", 0) >= 3600 or user_opts.time_format ~= "dynamic"
	local show_remhours = (state.tc_right_rem and remsec >= 3600)
		or (not state.tc_right_rem and dur >= 3600)
		or user_opts.time_format ~= "dynamic"
	local auto_hide_volbar = (audio_track and user_opts.volume_control)
		and osc_param.playresx < (user_opts.hide_volume_bar_trigger - outeroffset)
	local time_codes_x = start_x
		- (auto_hide_volbar and 75 or 0) -- window width with audio track and elements
		- (audio_track and not user_opts.volume_control and 115 or 0) -- audio track with no elements
		- (not audio_track and 12 or 0) -- remove extra padding
	local time_codes_width = 80
		+ (state.tc_ms and 50 or 0)
		+ (state.tc_right_rem and 15 or 0)
		+ (show_hours and 20 or 0)
		+ (show_remhours and 20 or 0)
	local narrow_win = osc_param.playresx
		< (
			user_opts.portrait_window_trigger
			- outeroffset
			- (playlist_button and 0 or 100)
			- (subtitle_track and 0 or 100)
			- (audio_track and 0 or 100)
		)
	lo = add_layout("time_codes")
	lo.geometry = {
		x = (narrow_win and refX or time_codes_x),
		y = refY - (narrow_win and user_opts.time_codes_centered_height or user_opts.time_codes_height),
		an = (narrow_win and 5 or 4),
		w = time_codes_width,
		h = user_opts.time_font_size,
	}
	lo.style = osc_styles.time

	-- Fullscreen/Info/Pin/Screenshot/Loop/Speed
	local end_x = osc_geo.w - 37
	if fullscreen_button then
		lo = add_layout("tog_fullscreen")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 250 - outeroffset)
		end_x = end_x - 45
	end

	if info_button then
		lo = add_layout("tog_info")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 300 - outeroffset)
		end_x = end_x - 45
	end

	if ontop_button then
		lo = add_layout("tog_ontop")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 500 - outeroffset)
		end_x = end_x - 45
	end

	if screenshot_button then
		lo = add_layout("screenshot")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 600 - outeroffset)
		end_x = end_x - 45
	end

	if loop_button then
		lo = add_layout("tog_loop")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 600 - outeroffset) and loop_button
		end_x = end_x - 45
	end

	if shuffle_button then
		lo = add_layout("tog_shuffle")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 600 - outeroffset) and shuffle_button
		end_x = end_x - 45
	end

	if speed_button then
		lo = add_layout("tog_speed")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 600 - outeroffset)
		end_x = end_x - 45
	end

	if download_button then
		lo = add_layout("download")
		lo.geometry = { x = end_x, y = refY - 35, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 400 - outeroffset)
		end_x = end_x - 45
	end

	-- cache info
	if user_opts.cache_info then
		lo = add_layout("cache_info")
		lo.geometry = { x = end_x + 7, y = refY - 35, an = 6, w = (user_opts.cache_info_speed and 70 or 45), h = 24 }
		lo.style = osc_styles.cache
	end
end

layouts["modern-image"] = function()
	local osc_geo = {
		w = osc_param.playresx,
		h = 50,
	}

	-- update bottom margin
	osc_param.video_margins.b = math.max(50, user_opts.fade_alpha) / osc_param.playresy

	-- origin of the controllers, left/bottom corner
	local posX = 0
	local posY = osc_param.playresy

	osc_param.areas = {} -- delete areas

	-- area for active mouse input
	add_area("input", get_hitbox_coords(posX, posY, 1, osc_geo.w, osc_geo.h))

	-- area for show/hide
	add_area("showhide", 0, 0, osc_param.playresx, osc_param.playresy)

	-- fetch values
	local osc_w, osc_h = osc_geo.w, osc_geo.h

	-- Controller Background
	local lo, geo

	new_element("osc_fade_bg", "box")
	lo = add_layout("osc_fade_bg")
	lo.geometry = { x = posX, y = posY, an = 7, w = osc_w, h = 1 }
	lo.style = osc_styles.osc_fade_bg
	lo.layer = 10
	lo.alpha[3] = user_opts.fade_transparency_strength

	local top_titlebar = window_controls_enabled() and (user_opts.show_window_title or user_opts.window_controls)

	-- Window bar alpha
	if
		((user_opts.window_top_bar == "yes" or not (state.border and state.title_bar)) or state.fullscreen)
		and top_titlebar
	then
		new_element("window_bar_alpha_bg", "box")
		lo = add_layout("window_bar_alpha_bg")
		lo.geometry = { x = posX, y = -100, an = 7, w = osc_w, h = -1 }
		lo.style = osc_styles.window_fade_bg
		lo.layer = 10
		lo.alpha[3] = user_opts.window_fade_transparency_strength
	end

	-- Alignment
	local refX = osc_w / 2
	local refY = posY

	local track_nextprev_buttons = user_opts.track_nextprev_buttons
	local fullscreen_button = user_opts.fullscreen_button
	local info_button = user_opts.info_button
	local ontop_button = user_opts.ontop_button
	local playlist_button = user_opts.playlist_button
		and (not user_opts.hide_empty_playlist_button or mp.get_property_number("playlist-count", 0) > 1)
	local zoom_control = user_opts.zoom_control

	-- Playlist
	if playlist_button then
		lo = add_layout("tog_playlist")
		lo.geometry = { x = 25, y = refY - 30, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = osc_param.playresx >= 250
	end

	if track_nextprev_buttons then
		lo = add_layout("playlist_prev")
		lo.geometry = { x = 55 - (playlist_button and 0 or 25), y = refY - 30, an = 5, w = 30, h = 24 }
		lo.style = osc_styles.control_2

		lo = add_layout("playlist_next")
		lo.geometry = { x = 80 - (playlist_button and 0 or 25), y = refY - 30, an = 5, w = 30, h = 24 }
		lo.style = osc_styles.control_2
	end

	if zoom_control then
		-- zoom control
		lo = add_layout("zoom_out_icon")
		lo.geometry = {
			x = 130 - (playlist_button and 0 or 25) - (track_nextprev_buttons and 0 or 70),
			y = refY - 30,
			an = 5,
			w = 30,
			h = 24,
		}
		lo.style = osc_styles.control_2

		lo = new_element("zoom_control_bg", "box")
		lo.visible = osc_param.playresx >= 400 and user_opts.zoom_control
		lo = add_layout("zoom_control_bg")
		lo.geometry = {
			x = 145 - (playlist_button and 0 or 25) - (track_nextprev_buttons and 0 or 70),
			y = refY - 30,
			an = 4,
			w = 80,
			h = 4,
		}
		lo.layer = 13
		lo.alpha[1] = 128
		lo.style = osc_styles.volumebar_bg

		lo = add_layout("zoom_control")
		lo.geometry = {
			x = 145 - (playlist_button and 0 or 25) - (track_nextprev_buttons and 0 or 70),
			y = refY - 30,
			an = 4,
			w = 80,
			h = 10,
		}
		lo.style = osc_styles.volumebar_fg
		lo.slider.gap = 3
		lo.slider.tooltip_style = osc_styles.tooltip
		lo.slider.tooltip_an = 2

		lo = add_layout("zoom_in_icon")
		lo.geometry = {
			x = 240 - (playlist_button and 0 or 25) - (track_nextprev_buttons and 0 or 70),
			y = refY - 30,
			an = 5,
			w = 30,
			h = 24,
		}
		lo.style = osc_styles.control_2
	end

	-- Fullscreen/Info/Pin/Download
	if fullscreen_button then
		lo = add_layout("tog_fullscreen")
		lo.geometry = { x = osc_geo.w - 37, y = refY - 30, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 250)
	end

	if info_button then
		lo = add_layout("tog_info")
		lo.geometry = { x = osc_geo.w - 82 + (fullscreen_button and 0 or 45), y = refY - 30, an = 5, w = 24, h = 24 }
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 300)
	end

	if ontop_button then
		lo = add_layout("tog_ontop")
		lo.geometry = {
			x = osc_geo.w - 127 + (info_button and 0 or 45) + (fullscreen_button and 0 or 45),
			y = refY - 30,
			an = 5,
			w = 24,
			h = 24,
		}
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 500)
	end

	if user_opts.download_button then
		lo = add_layout("download")
		lo.geometry = {
			x = osc_geo.w
				- 172
				+ (ontop_button and 0 or 45)
				+ (info_button and 0 or 45)
				+ (fullscreen_button and 0 or 45),
			y = refY - 30,
			an = 5,
			w = 24,
			h = 24,
		}
		lo.style = osc_styles.control_3
		lo.visible = (osc_param.playresx >= 400)
	end
end

local function adjust_subtitles(visible)
	if not mp.get_property_native("sid") then
		return
	end

	local scale = state.fullscreen and user_opts.scalefullscreen or user_opts.scalewindowed

	if visible and user_opts.raise_subtitles and state.osc_visible == true then
		local w, h = mp.get_osd_size()
		if h > 0 then
			local raise_factor = user_opts.raise_subtitle_amount

			-- adjust for scale
			if scale > 1 then
				raise_factor = raise_factor * (1 + (scale - 1) * 0.2)
			elseif scale < 1 then
				raise_factor = raise_factor * (0.8 + (scale - 0.5) * 0.5)
			end

			-- raise percentage
			local raise_percent = (raise_factor / osc_param.playresy) * 100

			-- don't adjust if user's sub-pos is higher than the raise factor
			if state.user_subpos >= (100 - raise_percent) then
				local adjusted = math.floor((osc_param.playresy - raise_factor) / osc_param.playresy * 100)
				if adjusted < 0 then
					adjusted = state.user_subpos
				end

				state.osc_adjusted_subpos = adjusted
				mp.set_property_number("sub-pos", adjusted)
			else
				state.osc_adjusted_subpos = nil
			end
		end
	elseif user_opts.raise_subtitles then
		-- restore user's original subtitle position
		if state.user_subpos then
			mp.set_property_number("sub-pos", state.user_subpos)
		end
		state.osc_adjusted_subpos = nil
	end
end

local function is_image()
	local current_track = mp.get_property_native("current-tracks/video")
	if current_track and current_track.image and not current_track.albumart then
		state.is_image = true
	else
		state.is_image = false
	end
end

local function osc_visible(visible)
	if state.osc_visible ~= visible then
		state.osc_visible = visible
		update_margins()
		adjust_subtitles(true)
	end
	request_tick()
end

local function command_callback(command)
	if command ~= "" and command ~= "ignore" then
		return function()
			mp.command(command)
		end
	end
end

local function osc_init()
	msg.debug("osc_init")

	-- set canvas resolution according to display aspect and scaling setting
	local baseResY = 720
	local _, display_h, display_aspect = mp.get_osd_size()
	local scale

	if state.fullscreen then
		scale = user_opts.scalefullscreen
	else
		scale = user_opts.scalewindowed
	end

	local scale_with_video
	if user_opts.vidscale == "auto" then
		scale_with_video = mp.get_property_native("osd-scale-by-window")
	else
		scale_with_video = user_opts.vidscale == "yes"
	end

	if scale_with_video then
		osc_param.unscaled_y = baseResY
	else
		osc_param.unscaled_y = display_h
	end
	osc_param.playresy = osc_param.unscaled_y / scale
	if display_aspect > 0 then
		osc_param.display_aspect = display_aspect
	end
	osc_param.playresx = osc_param.playresy * osc_param.display_aspect

	-- stop seeking with the slider to prevent skipping files
	state.active_element = nil

	elements = {}

	-- some often needed stuff
	local pl_count = mp.get_property_number("playlist-count", 0)
	local have_pl = pl_count > 1
	local pl_pos = mp.get_property_number("playlist-pos", 0) + 1
	local have_ch = mp.get_property_number("chapters", 0) > 0
	local loop = mp.get_property("loop-playlist", "no")

	local nojumpoffset = user_opts.jump_buttons and 0 or 100
	local noskipoffset = user_opts.chapter_skip_buttons and 0 or 100
	local outeroffset = (user_opts.chapter_skip_buttons and 0 or 100) + (user_opts.jump_buttons and 0 or 100)
	local audio_offset = (audio_track_count == 0 or not mp.get_property_native("aid")) and 100 or 0
	local sub_offset = (sub_track_count == 0 or not mp.get_property_native("sid")) and 100 or 0
	local playlist_offset = not have_pl and 100 or 0

	local ne

	-- Window controls
	-- Close: 🗙
	ne = new_element("close", "button")
	ne.content = icons.window.close
	ne.eventresponder["mbtn_left_up"] = function()
		mp.commandv("quit")
	end

	-- Minimize: 🗕
	ne = new_element("minimize", "button")
	ne.content = icons.window.minimize
	ne.eventresponder["mbtn_left_up"] = function()
		mp.commandv("cycle", "window-minimized")
	end

	-- Maximize: 🗖 /🗗
	ne = new_element("maximize", "button")
	ne.content = (state.maximized or state.fullscreen) and icons.window.unmaximize or icons.window.maximize
	ne.eventresponder["mbtn_left_up"] = function()
		mp.commandv("cycle", (state.fullscreen and "fullscreen" or "window-maximized"))
	end

	-- Window Title
	ne = new_element("windowtitle", "button")
	ne.content = function()
		local title = mp.command_native({ "expand-text", user_opts.window_title }) or ""
		title = title:gsub("\n", " ")
		return title ~= "" and mp.command_native({ "escape-ass", title }) or "mpv"
	end

	-- OSC title
	ne = new_element("title", "button")
	ne.visible = user_opts.show_title
	ne.content = function()
		local title = state.forced_title or mp.command_native({ "expand-text", user_opts.title })
		title = title:gsub("\n", " ")
		return title ~= "" and mp.command_native({ "escape-ass", title }) or "mpv"
	end
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.title_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.title_mbtn_right_command)
	ne.eventresponder["shift+mbtn_left_down"] = command_callback(user_opts.title_mbtn_mid_command)

	-- Chapter title (above seekbar)
	ne = new_element("chapter_title", "button")
	ne.visible = mp.get_property_number("chapter", -1) >= 0
	ne.content = function()
		local chapter_index = mp.get_property_number("chapter", -1)
		if user_opts.chapter_fmt == "no" or chapter_index < 0 then
			return ""
		end

		local chapters = mp.get_property_native("chapter-list", {})
		local chapter_data = chapters[chapter_index + 1]
		local chapter_title = chapter_data and chapter_data.title ~= "" and chapter_data.title
			or string.format("%s: %d/%d", locale.chapter, chapter_index + 1, #chapters)

		chapter_title = mp.command_native({ "escape-ass", chapter_title })
		if thumbfast.disabled and not user_opts.show_title and state.forced_title then
			chapter_title = state.forced_title
		end

		return string.format(user_opts.chapter_fmt, chapter_title)
	end
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.chapter_title_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.chapter_title_mbtn_right_command)

	-- playlist buttons
	-- prev
	ne = new_element("playlist_prev", "button")
	ne.visible = (
		osc_param.playresx
		>= (state.is_image and 300 or 500) - nojumpoffset - noskipoffset * (nojumpoffset == 0 and 1 or 10)
	)
	ne.content = icons.previous
	ne.enabled = (pl_pos > 1) or (loop ~= "no") or contains(user_opts.buttons_always_active, "playlist_prev")
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.playlist_prev_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.playlist_prev_mbtn_right_command)
	ne.eventresponder["shift+mbtn_left_down"] = command_callback(user_opts.playlist_prev_mbtn_mid_command)

	--next
	ne = new_element("playlist_next", "button")
	ne.visible = (
		osc_param.playresx
		>= (state.is_image and 300 or 500) - nojumpoffset - noskipoffset * (nojumpoffset == 0 and 1 or 10)
	)
	ne.content = icons.next
	ne.enabled = (have_pl and (pl_pos < pl_count))
		or (loop ~= "no")
		or contains(user_opts.buttons_always_active, "playlist_next")
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.playlist_next_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.playlist_next_mbtn_right_command)
	ne.eventresponder["shift+mbtn_left_down"] = command_callback(user_opts.playlist_next_mbtn_mid_command)

	--play control buttons
	--play_pause
	ne = new_element("play_pause", "button")
	ne.content = function()
		if mp.get_property("eof-reached") == "yes" then
			return icons.replay
		elseif mp.get_property("pause") == "yes" and not state.playing_and_seeking then
			return icons.play
		else
			return icons.pause
		end
	end
	ne.eventresponder["mbtn_left_up"] = function()
		if mp.get_property("eof-reached") == "yes" then
			mp.commandv("seek", 0, "absolute-percent")
			mp.commandv("set", "pause", "no")
		else
			mp.commandv("cycle", "pause")
		end
	end
	ne.eventresponder["mbtn_right_down"] = function()
		if user_opts.loop_in_pause then
			mp.command("show-text '" .. (state.looping and locale.loop_disable or locale.loop_enable) .. "'")
			state.looping = not state.looping
			mp.set_property_native("loop-file", state.looping)
		end
	end

	local jump_amount = user_opts.jump_amount
	local jump_more_amount = user_opts.jump_more_amount
	local jump_mode = user_opts.jump_mode
	local jump_icon = user_opts.jump_icon_number and icons.jump[jump_amount] or icons.jump.default

	--jump_backward
	ne = new_element("jump_backward", "button")
	ne.softrepeat = user_opts.jump_softrepeat == true
	ne.content = jump_icon[1]
	ne.eventresponder["mbtn_left_down"] = function()
		mp.commandv("seek", -jump_amount, jump_mode)
	end
	ne.eventresponder["mbtn_right_down"] = function()
		mp.commandv("seek", -jump_more_amount, jump_mode)
	end
	ne.eventresponder["shift+mbtn_left_down"] = function()
		mp.commandv("frame-back-step")
	end

	--jump_forward
	ne = new_element("jump_forward", "button")
	ne.softrepeat = user_opts.jump_softrepeat == true
	ne.content = jump_icon[2]
	ne.eventresponder["mbtn_left_down"] = function()
		mp.commandv("seek", jump_amount, jump_mode)
	end
	ne.eventresponder["mbtn_right_down"] = function()
		mp.commandv("seek", jump_more_amount, jump_mode)
	end
	ne.eventresponder["shift+mbtn_left_down"] = function()
		mp.commandv("frame-step")
	end

	--chapter_backward
	ne = new_element("chapter_backward", "button")
	ne.visible = (osc_param.playresx >= 400 - nojumpoffset * 10)
	ne.softrepeat = user_opts.chapter_softrepeat == true
	ne.content = icons.rewind
	ne.enabled = have_ch -- disables button when no chapters available.
	ne.eventresponder["mbtn_left_down"] = command_callback(user_opts.chapter_prev_mbtn_left_command)
	ne.eventresponder["mbtn_right_down"] = command_callback(user_opts.chapter_prev_mbtn_right_command)
	ne.eventresponder["shift+mbtn_left_down"] = command_callback(user_opts.chapter_prev_mbtn_mid_command)
	ne.eventresponder["shift+mbtn_right_down"] = function()
		mp.commandv("seek", -jump_more_amount, jump_mode)
	end

	--chapter_forward
	ne = new_element("chapter_forward", "button")
	ne.visible = (osc_param.playresx >= 400 - nojumpoffset * 10)
	ne.softrepeat = user_opts.chapter_softrepeat == true
	ne.content = icons.forward
	ne.enabled = have_ch -- disables button when no chapters available.
	ne.eventresponder["mbtn_left_down"] = command_callback(user_opts.chapter_next_mbtn_left_command)
	ne.eventresponder["mbtn_right_down"] = command_callback(user_opts.chapter_next_mbtn_right_command)
	ne.eventresponder["shift+mbtn_left_down"] = command_callback(user_opts.chapter_next_mbtn_mid_command)
	ne.eventresponder["shift+mbtn_right_down"] = function()
		mp.commandv("seek", jump_more_amount, jump_mode)
	end

	update_tracklist()

	local visible_min_width = 550 - outeroffset

	--tog_playlist
	ne = new_element("tog_playlist", "button")
	ne.enabled = have_pl or not user_opts.gray_empty_playlist_button
	ne.off = not have_pl and user_opts.gray_empty_playlist_button
	ne.visible = (osc_param.playresx >= (state.is_image and 250 or visible_min_width) - outeroffset)
	ne.content = icons.playlist
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = user_opts.tooltip_hints and locale.menu or ""
	ne.nothingavailable = locale.no_playlist
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.playlist_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.playlist_mbtn_right_command)
	visible_min_width = visible_min_width + (ne.enabled and 100 or 0)

	--audio_track
	ne = new_element("audio_track", "button")
	ne.enabled = audio_track_count > 0
	ne.off = audio_track_count == 0 or not mp.get_property_native("aid")
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.content = icons.audio
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = function()
		local prop = mp.get_property("current-tracks/audio/title")
			or mp.get_property("current-tracks/audio/lang")
			or locale.na
		return (
			locale.audio
			.. " "
			.. mp.get_property_number("aid", "-")
			.. "/"
			.. audio_track_count
			.. " ["
			.. prop
			.. "]"
		)
	end
	ne.nothingavailable = locale.no_audio
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.audio_track_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.audio_track_mbtn_right_command)
	ne.eventresponder["shift+mbtn_left_down"] = command_callback(user_opts.audio_track_mbtn_mid_command)
	ne.eventresponder["wheel_down_press"] = command_callback(user_opts.audio_track_wheel_down_command)
	ne.eventresponder["wheel_up_press"] = command_callback(user_opts.audio_track_wheel_up_command)
	visible_min_width = visible_min_width + (ne.enabled and 100 or 0)

	--sub_track
	ne = new_element("sub_track", "button")
	ne.enabled = sub_track_count > 0
	ne.off = sub_track_count == 0 or not mp.get_property_native("sid")
	ne.visible = (osc_param.playresx >= visible_min_width - outeroffset)
	ne.content = icons.subtitle
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = function()
		local prop = mp.get_property("current-tracks/sub/title")
			or mp.get_property("current-tracks/sub/lang")
			or locale.na
		return (
			locale.subtitle
			.. " "
			.. mp.get_property_number("sid", "-")
			.. "/"
			.. sub_track_count
			.. " ["
			.. prop
			.. "]"
		)
	end
	ne.nothingavailable = locale.no_subs
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.sub_track_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.sub_track_mbtn_right_command)
	ne.eventresponder["shift+mbtn_left_down"] = command_callback(user_opts.sub_track_mbtn_mid_command)
	ne.eventresponder["wheel_down_press"] = command_callback(user_opts.sub_track_wheel_down_command)
	ne.eventresponder["wheel_up_press"] = command_callback(user_opts.sub_track_wheel_up_command)
	visible_min_width = visible_min_width + (ne.enabled and 100 or 0)

	-- vol_ctrl
	local vol_visible_offset = sub_offset + playlist_offset
	ne = new_element("vol_ctrl", "button")
	ne.enabled = audio_track_count > 0
	ne.off = audio_track_count == 0
	ne.visible = (osc_param.playresx >= 900 - vol_visible_offset - outeroffset) and user_opts.volume_control
	ne.content = function()
		local volume = mp.get_property_number("volume", 0)
		if state.mute then
			return icons.volume_mute
		else
			if volume >= 75 then
				return icons.volume_high
			elseif volume >= 25 then
				return icons.volume_low
			else
				return icons.volume_quiet
			end
		end
	end
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = function()
		local volume = mp.get_property_number("volume", 0) or 0
		-- show only one decimal, if decimals exist
		volume = volume % 1 == 0 and string.format("%.0f", volume) or string.format("%.1f", volume)
		return volume
	end
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.vol_ctrl_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.vol_ctrl_mbtn_right_command)
	ne.eventresponder["wheel_up_press"] = command_callback(user_opts.vol_ctrl_wheel_up_command)
	ne.eventresponder["wheel_down_press"] = command_callback(user_opts.vol_ctrl_wheel_down_command)

	--volumebar
	local volume_max = mp.get_property_number("volume-max") > 0 and mp.get_property_number("volume-max") or 100
	ne = new_element("volumebar", "slider")
	ne.visible = (osc_param.playresx >= 1150 - outeroffset) and user_opts.volume_control
	ne.enabled = audio_track_count > 0
	ne.slider = { min = { value = 0 }, max = { value = volume_max } }
	ne.slider.markerF = function()
		return {}
	end
	ne.slider.seekRangesF = function()
		return nil
	end
	ne.slider.posF = function()
		local volume = mp.get_property_number("volume")
		if user_opts.volume_control == "logarithmic" then
			return math.sqrt(volume * 100)
		else
			return volume
		end
	end
	ne.slider.tooltipF = function(pos)
		return (audio_track_count > 0) and set_volume(pos) or ""
	end
	ne.eventresponder["mouse_move"] = function(element)
		local pos = get_slider_value(element)
		local setvol = set_volume(pos)
		if element.state.lastseek == nil or element.state.lastseek ~= setvol then
			mp.commandv("osd-msg", "set", "volume", setvol)
			element.state.lastseek = setvol
		end
	end
	ne.eventresponder["mbtn_left_down"] = function(element)
		local pos = get_slider_value(element)
		mp.commandv("osd-msg", "set", "volume", set_volume(pos))
	end
	ne.eventresponder["reset"] = function(element)
		element.state.lastseek = nil
	end
	ne.eventresponder["wheel_up_press"] = command_callback(user_opts.vol_ctrl_wheel_up_command)
	ne.eventresponder["wheel_down_press"] = command_callback(user_opts.vol_ctrl_wheel_down_command)

	-- zoom control
	-- zoom out icon
	local current_zoom = mp.get_property_number("video-zoom")
	ne = new_element("zoom_out_icon", "button")
	ne.visible = (osc_param.playresx >= 400)
	ne.content = icons.zoom_out
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = user_opts.tooltip_hints and locale.zoom_out or ""
	ne.eventresponder["mbtn_left_up"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.max(user_opts.zoom_out_min, current_zoom - 0.05))
	end
	ne.eventresponder["mbtn_right_up"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", 0)
	end
	ne.eventresponder["wheel_up_press"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.min(user_opts.zoom_in_max, current_zoom + 0.05))
	end
	ne.eventresponder["wheel_down_press"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.max(user_opts.zoom_out_min, current_zoom - 0.05))
	end

	-- zoom slider
	ne = new_element("zoom_control", "slider")
	ne.slider = { min = { value = user_opts.zoom_out_min }, max = { value = user_opts.zoom_in_max } }
	ne.visible = (osc_param.playresx >= 400) and user_opts.zoom_control and state.is_image
	ne.slider.markerF = function()
		return {}
	end
	ne.slider.seekRangesF = function()
		return nil
	end
	ne.slider.posF = function()
		return mp.get_property_number("video-zoom")
	end
	ne.slider.tooltipF = function(pos)
		return string.format("%.3f", pos):gsub("%.?0*$", "")
	end
	ne.eventresponder["mouse_move"] = function(element)
		local pos = get_slider_value(element)
		if element.state.lastseek == nil or element.state.lastseek ~= pos then
			mp.commandv("osd-msg", "set", "video-zoom", pos)
			element.state.lastseek = pos
		end
	end
	ne.eventresponder["mbtn_left_down"] = function(element)
		mp.commandv("osd-msg", "set", "video-zoom", get_slider_value(element))
	end
	ne.eventresponder["reset"] = function(element)
		element.state.lastseek = nil
	end
	ne.eventresponder["mbtn_right_up"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", 0)
	end
	ne.eventresponder["wheel_up_press"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.min(user_opts.zoom_in_max, current_zoom + 0.05))
	end
	ne.eventresponder["wheel_down_press"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.max(user_opts.zoom_out_min, current_zoom - 0.05))
	end

	-- zoom in icon
	ne = new_element("zoom_in_icon", "button")
	ne.visible = (osc_param.playresx >= 400)
	ne.content = icons.zoom_in
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = user_opts.tooltip_hints and locale.zoom_in or ""
	ne.eventresponder["mbtn_left_up"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.min(user_opts.zoom_in_max, current_zoom + 0.05))
	end
	ne.eventresponder["mbtn_right_up"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", 0)
	end
	ne.eventresponder["wheel_up_press"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.min(user_opts.zoom_in_max, current_zoom + 0.05))
	end
	ne.eventresponder["wheel_down_press"] = function()
		mp.commandv("osd-msg", "set", "video-zoom", math.max(user_opts.zoom_out_min, current_zoom - 0.05))
	end

	visible_min_width = 550 - outeroffset
	--tog_fullscreen
	ne = new_element("tog_fullscreen", "button")
	ne.content = function()
		return state.fullscreen and icons.fullscreen_exit or icons.fullscreen
	end
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.fullscreen_mbtn_left_command)
	ne.eventresponder["mbtn_right_up"] = command_callback(user_opts.fullscreen_mbtn_right_command)
	visible_min_width = visible_min_width + (user_opts.fullscreen_button and 100 or 0)

	--tog_info
	ne = new_element("tog_info", "button")
	ne.content = icons.info
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = user_opts.tooltip_hints and locale.stats_info or ""
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.info_mbtn_left_command)
	visible_min_width = visible_min_width + (user_opts.info_button and 100 or 0)

	--tog_ontop
	ne = new_element("tog_ontop", "button")
	ne.content = function()
		return mp.get_property("ontop") == "no" and icons.ontop_on or icons.ontop_off
	end
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = function()
		return user_opts.tooltip_hints and (mp.get_property("ontop") == "no" and locale.ontop or locale.ontop_disable)
			or ""
	end
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.eventresponder["mbtn_left_up"] = function()
		mp.commandv("cycle", "ontop")
		if state.initialborder == "yes" then
			if mp.get_property("ontop") == "yes" then
				mp.commandv("set", "border", "no")
			else
				mp.commandv("set", "border", "yes")
			end
		end
	end
	ne.eventresponder["mbtn_right_up"] = function()
		mp.commandv("cycle", "ontop")
		if mp.get_property("border") == "no" then
			mp.commandv("set", "border", "yes")
		end
	end
	visible_min_width = visible_min_width + (user_opts.ontop_button and 100 or 0)

	--screenshot
	ne = new_element("screenshot", "button")
	ne.content = icons.screenshot
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = user_opts.tooltip_hints and locale.screenshot or ""
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.eventresponder["mbtn_left_up"] = command_callback(user_opts.screenshot_mbtn_left_command)
	visible_min_width = visible_min_width + (user_opts.screenshot_button and 100 or 0)

	--tog_loop
	ne = new_element("tog_loop", "button")
	ne.content = function()
		return state.looping and icons.loop_on or icons.loop_off
	end
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = function()
		return user_opts.tooltip_hints and (state.looping and locale.loop_disable or locale.loop_enable) or ""
	end
	ne.eventresponder["mbtn_left_up"] = function()
		mp.command("show-text '" .. (state.looping and locale.loop_disable or locale.loop_enable) .. "'")
		state.looping = not state.looping
		mp.set_property_native("loop-file", state.looping)
	end
	visible_min_width = visible_min_width + (user_opts.loop_button and 100 or 0)

	--tog_shuffle
	ne = new_element("tog_shuffle", "button")
	ne.content = function()
		return state.shuffled and icons.shuffle_on or icons.shuffle_off
	end
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = function()
		return user_opts.tooltip_hints and (state.shuffled and locale.unshuffle or locale.shuffle) or ""
	end
	ne.eventresponder["mbtn_left_up"] = function()
		mp.command("show-text '" .. (state.shuffled and locale.unshuffle or locale.shuffle) .. "'")
		state.shuffled = not state.shuffled
		if state.shuffled then
			mp.command("playlist-shuffle")
		else
			mp.command("playlist-unshuffle")
		end
	end
	visible_min_width = visible_min_width + (user_opts.loop_button and 100 or 0)

	--tog_speed
	ne = new_element("tog_speed", "button")
	ne.content = icons.speed
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = user_opts.tooltip_hints and locale.speed_control or ""
	ne.eventresponder["mbtn_left_up"] = function()
		mp.commandv(
			"osd-msg",
			"set",
			"speed",
			math.min(100, mp.get_property_number("speed") + user_opts.speed_button_click)
		)
	end
	ne.eventresponder["mbtn_right_up"] = function()
		mp.commandv("osd-msg", "set", "speed", 1)
	end
	ne.eventresponder["wheel_up_press"] = function()
		mp.commandv(
			"osd-msg",
			"set",
			"speed",
			math.min(100, mp.get_property_number("speed") + user_opts.speed_button_scroll)
		)
	end
	ne.eventresponder["wheel_down_press"] = function()
		mp.commandv(
			"osd-msg",
			"set",
			"speed",
			math.max(0.25, mp.get_property_number("speed") - user_opts.speed_button_scroll)
		)
	end
	visible_min_width = visible_min_width + (user_opts.speed_button and 100 or 0)

	--download
	ne = new_element("download", "button")
	ne.content = function()
		return state.downloading and icons.downloading or icons.download
	end
	ne.visible = (osc_param.playresx >= visible_min_width) and state.is_URL
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = function()
		return state.downloading and locale.downloading .. "..."
			or locale.download .. " (" .. state.file_size_normalized .. ")"
	end
	ne.eventresponder["mbtn_left_up"] = function()
		local localpath = mp.command_native({ "expand-path", user_opts.download_path })

		if state.downloaded_once then
			mp.commandv("show-text", locale.downloaded)
		elseif state.downloading then
			mp.commandv("show-text", locale.download_in_progress)
		else
			mp.commandv("show-text", locale.downloading .. "...")
			state.downloading = true
			-- use current or default ytdl-format
			local mpv_ytdl = mp.get_property("file-local-options/ytdl-format") or mp.get_property("ytdl-format") or ""
			local ytdl_format = (mpv_ytdl and mpv_ytdl ~= "") and mpv_ytdl
				or "bestvideo+bestaudio/best"
			local command = {
				"yt-dlp",
			}
			if not state.is_image then
				table.insert(command, "-f")
				table.insert(command, ytdl_format)
			end
			table.insert(command, "--add-metadata")
			table.insert(command, "--embed-subs")
			table.insert(command, "-o")
			table.insert(command, "%(title)s.%(ext)s")
			table.insert(command, "-P")
			table.insert(command, localpath)
			table.insert(command, state.url_path)

			local status = exec(command, download_done)
		end
	end
	visible_min_width = visible_min_width + (user_opts.download_button and 100 or 0)

	-- cache info
	ne = new_element("cache_info", "button")
	ne.visible = (osc_param.playresx >= visible_min_width)
	ne.content = function()
		if not cache_enabled() then
			return ""
		end
		local dmx_cache = state.cache_state["cache-duration"]
		local thresh = math.min(state.dmx_cache * 0.05, 5) -- 5% or 5s
		if dmx_cache and math.abs(dmx_cache - state.dmx_cache) >= thresh then
			state.dmx_cache = dmx_cache
		else
			dmx_cache = state.dmx_cache
		end
		local min = math.floor(dmx_cache / 60)
		local sec = math.floor(dmx_cache % 60) -- don't round e.g. 59.9 to 60
		local cache_time = (min > 0 and string.format("%sm%02.0fs", min, sec) or string.format("%3.0fs", sec))

		local dmx_speed = state.cache_state["raw-input-rate"] or 0
		local cache_speed = utils.format_bytes_humanized(dmx_speed)
		local number, unit = cache_speed:match("([%d%.]+)%s*(%S+)")
		local cache_info = state.buffering
				and locale.buffering .. ": " .. mp.get_property("cache-buffering-state") .. "%"
			or cache_time
		local cache_info_speed = string.format("%8s %4s/s", number, unit)

		return user_opts.cache_info_speed and cache_info .. "\\N" .. cache_info_speed or cache_info
	end
	ne.tooltip_style = osc_styles.tooltip
	ne.tooltipF = (user_opts.tooltip_hints and cache_enabled()) and locale.cache or ""
	ne.eventresponder["mbtn_left_up"] = function()
		mp.command("script-binding stats/display-page-3")
	end

	--seekbar
	ne = new_element("seekbar", "slider")
	ne.enabled = mp.get_property("percent-pos") ~= nil
	ne.thumbnailable = true
	state.slider_element = ne.enabled and ne or nil -- used for forced_title
	ne.slider.markerF = function()
		local duration = mp.get_property_number("duration")
		if duration ~= nil then
			local chapters = mp.get_property_native("chapter-list", {})
			local markers = {}
			for n = 1, #chapters do
				markers[n] = (chapters[n].time / duration * 100)
			end
			return markers
		else
			return {}
		end
	end
	ne.slider.posF = function()
		if mp.get_property_bool("eof-reached") then
			return 100
		end
		return mp.get_property_number("percent-pos")
	end
	ne.slider.tooltipF = function(pos)
		state.touchingprogressbar = true
		local duration = mp.get_property_number("duration")
		if duration ~= nil and pos ~= nil then
			local possec = duration * (pos / 100)
			local time = mp.format_time(possec)
			-- If video is less than 1 hour, and the time format is not fixed, strip the "00:" prefix
			if possec < 3600 and user_opts.time_format ~= "fixed" then
				time = time:gsub("^00:", "")
			end
			return time
		else
			return ""
		end
	end
	ne.slider.seekRangesF = function()
		if not user_opts.seekrange or not cache_enabled() then
			return nil
		end
		local duration = mp.get_property_number("duration")
		if duration == nil or duration <= 0 then
			return nil
		end
		local nranges = {}
		for _, range in pairs(state.cache_state["seekable-ranges"]) do
			nranges[#nranges + 1] = {
				["start"] = 100 * range["start"] / duration,
				["end"] = 100 * range["end"] / duration,
			}
		end
		return nranges
	end
	ne.eventresponder["mouse_move"] = function(element)
		if not element.state.mbtnleft then
			return
		end -- allow drag for mbtnleft only!
		-- mouse move events may pile up during seeking and may still get
		-- sent when the user is done seeking, so we need to throw away
		-- identical seeks
		state.playing_and_seeking = true
		if mp.get_property("pause") == "no" and user_opts.mouse_seek_pause then
			mp.commandv("cycle", "pause")
		end
		local seekto = get_slider_value(element)
		if element.state.lastseek == nil or element.state.lastseek ~= seekto then
			local flags = "absolute-percent"
			if not user_opts.seekbarkeyframes then
				flags = flags .. "+exact"
			end
			mp.commandv("seek", seekto, flags)
			element.state.lastseek = seekto
		end
	end
	ne.eventresponder["mbtn_left_down"] = function(element)
		element.state.mbtnleft = true
		mp.commandv("seek", get_slider_value(element), "absolute-percent+exact")
	end
	ne.eventresponder["shift+mbtn_left_down"] = function(element)
		element.state.mbtnleft = true
		mp.commandv("seek", get_slider_value(element), "absolute-percent")
	end
	ne.eventresponder["mbtn_left_up"] = function(element)
		element.state.mbtnleft = false
	end
	ne.eventresponder["mbtn_right_down"] = function(element)
		local chapter
		local pos = get_slider_value(element)
		local diff = math.huge

		for i, marker in ipairs(element.slider.markerF()) do
			if math.abs(pos - marker) < diff then
				diff = math.abs(pos - marker)
				chapter = i
			end
		end

		if chapter then
			mp.set_property("chapter", chapter - 1)
		end
	end
	ne.eventresponder["reset"] = function(element)
		element.state.lastseek = nil
		if state.playing_and_seeking then
			if mp.get_property("eof-reached") == "no" and user_opts.mouse_seek_pause then
				mp.commandv("cycle", "pause")
			end
			state.playing_and_seeking = false
		end
	end
	ne.eventresponder["wheel_up_press"] = function()
		mp.commandv("seek", 10)
	end
	ne.eventresponder["wheel_down_press"] = function()
		mp.commandv("seek", -10)
	end

	--persistent seekbar
	ne = new_element("persistentseekbar", "slider")
	ne.enabled = mp.get_property("percent-pos") ~= nil
	state.slider_element = ne.enabled and ne or nil -- used for forced_title
	ne.slider.markerF = function()
		return {}
	end
	ne.slider.posF = function()
		if mp.get_property_bool("eof-reached") then
			return 100
		end
		return mp.get_property_number("percent-pos")
	end
	ne.slider.tooltipF = function()
		return ""
	end
	ne.slider.seekRangesF = function()
		if user_opts.persistentbuffer then
			if not user_opts.seekrange then
				return nil
			end
			local cache_state = state.cache_state
			if not cache_state then
				return nil
			end
			local duration = mp.get_property_number("duration")
			if duration == nil or duration <= 0 then
				return nil
			end
			local ranges = cache_state["seekable-ranges"]
			if #ranges == 0 then
				return nil
			end
			local nranges = {}
			for _, range in pairs(ranges) do
				nranges[#nranges + 1] = {
					["start"] = 100 * range["start"] / duration,
					["end"] = 100 * range["end"] / duration,
				}
			end
			return nranges
		end
		return nil
	end

	-- Helper function to format time
	local function format_time(seconds)
		if not seconds then
			return "--:--"
		end

		local hours = math.floor(seconds / 3600)
		local minutes = math.floor((seconds % 3600) / 60)
		local whole_seconds = math.floor(seconds % 60)
		local milliseconds = state.tc_ms and math.floor((seconds % 1) * 1000) or nil

		-- Always show HH:MM:SS if user_opts.time_format is "fixed"
		local force_hours = user_opts.time_format == "fixed"

		-- Format string templates
		local format_with_ms = (hours > 0 or force_hours) and "%02d:%02d:%02d.%03d" or "%02d:%02d.%03d"
		local format_without_ms = (hours > 0 or force_hours) and "%02d:%02d:%02d" or "%02d:%02d"

		if state.tc_ms then
			return string.format(
				format_with_ms,
				(hours > 0 or force_hours) and hours or minutes,
				(hours > 0 or force_hours) and minutes or whole_seconds,
				(hours > 0 or force_hours) and whole_seconds or milliseconds,
				(hours > 0 or force_hours) and milliseconds or nil
			)
		else
			return string.format(
				format_without_ms,
				(hours > 0 or force_hours) and hours or minutes,
				(hours > 0 or force_hours) and minutes or whole_seconds,
				(hours > 0 or force_hours) and whole_seconds or nil
			)
		end
	end

	-- Time codes display
	local tc_visible_offset = audio_offset + sub_offset + playlist_offset
	ne = new_element("time_codes", "button")
	ne.visible = mp.get_property_number("duration", 0) > 0
	ne.content = function()
		local playback_time = mp.get_property_number("playback-time", 0)

		-- call request_init() only when needed to update time code width
		if user_opts.time_format ~= "fixed" and playback_time then
			local hour_or_more = playback_time >= 3600
			if hour_or_more ~= state.playtime_hour_force_init then
				request_init()
				state.playtime_hour_force_init = hour_or_more
				state.playtime_nohour_force_init = not hour_or_more
			end
		end

		local duration = mp.get_property_number("duration", 0)
		if duration <= 0 then
			return "--:--"
		end

		local playtime_remaining = state.tc_right_rem and mp.get_property_number("playtime-remaining", 0) or duration

		local prefix = state.tc_right_rem and (user_opts.unicodeminus and UNICODE_MINUS or "-") or ""

		return format_time(playback_time) .. " / " .. prefix .. format_time(playtime_remaining)
	end
	ne.eventresponder["mbtn_left_up"] = function()
		state.tc_right_rem = not state.tc_right_rem
	end
	ne.eventresponder["mbtn_right_up"] = function()
		state.tc_ms = not state.tc_ms
		request_init()
	end

	-- load layout
	if state.is_image then
		layouts["modern-image"]()
	else
		layouts["modern"]()
	end

	-- load window controls
	if window_controls_enabled() then
		window_controls()
	end

	--do something with the elements
	prepare_elements()
	update_margins()
end

local function show_osc()
	-- show when disabled can happen (e.g. mouse_move) due to async/delayed unbinding
	if not state.enabled then
		return
	end

	msg.trace("show_osc")
	--remember last time of invocation (mouse move)
	state.showtime = mp.get_time()

	if user_opts.fadeduration <= 0 then
		osc_visible(true)
	elseif user_opts.fadein then
		if not state.osc_visible then
			state.anitype = "in"
			request_tick()
		end
	else
		osc_visible(true)
		state.anitype = nil
	end
end

local function hide_osc()
	msg.trace("hide_osc")
	if thumbfast.width ~= 0 and thumbfast.height ~= 0 then
		mp.commandv("script-message-to", "thumbfast", "clear")
	end
	if not state.enabled then
		-- typically hide happens at render() from tick(), but now tick() is
		-- no-op and won't render again to remove the osc, so do that manually.
		state.osc_visible = false
		adjust_subtitles(false)
		render_wipe()
	elseif user_opts.fadeduration > 0 then
		if state.osc_visible then
			state.anitype = "out"
			request_tick()
		end
	else
		osc_visible(false)
	end
end

local function pause_state(_, enabled)
	state.paused = enabled
	request_tick()
end

local function cache_state(_, st)
	state.cache_state = st
	request_tick()
end

local function mouse_leave()
	state.touchtime = nil

	if get_hidetimeout() >= 0 and get_touchtimeout() <= 0 then
		local elapsed_time = mp.get_time() - state.showtime

		if elapsed_time >= (get_hidetimeout() / 1000) then
			hide_osc()
		end
	end

	-- reset mouse position
	state.last_mouseX, state.last_mouseY = nil, nil
	state.mouse_in_window = false
end

local function handle_touch(_, touchpoints)
	--remember last touch points
	if touchpoints then
		state.touchpoints = touchpoints
		if #touchpoints > 0 then
			--remember last time of invocation (touch event)
			state.touchtime = mp.get_time()
			state.last_touchX = touchpoints[1].x
			state.last_touchY = touchpoints[1].y
		end
	end
end

--
-- Event handling
--
local function reset_timeout()
	state.showtime = mp.get_time()
end

local function element_has_action(element, action)
	return element and element.eventresponder and element.eventresponder[action]
end

local function process_event(source, what)
	local action = string.format("%s%s", source, what and ("_" .. what) or "")

	if what == "down" or what == "press" then
		reset_timeout() -- clicking resets the hideosc timer

		for n = 1, #elements do
			if
				mouse_hit(elements[n])
				and elements[n].eventresponder
				and (elements[n].eventresponder[source .. "_up"] or elements[n].eventresponder[action])
			then
				if what == "down" then
					state.active_element = n
					state.active_event_source = source
				end
				-- fire the down or press event if the element has one
				if element_has_action(elements[n], action) then
					elements[n].eventresponder[action](elements[n])
				end
			end
		end
	elseif what == "up" then
		if elements[state.active_element] then
			local n = state.active_element

			if n == 0 then
				--click on background (does not work)
			elseif element_has_action(elements[n], action) and mouse_hit(elements[n]) then
				elements[n].eventresponder[action](elements[n])
			end

			--reset active element
			if element_has_action(elements[n], "reset") then
				elements[n].eventresponder["reset"](elements[n])
			end
		end
		state.active_element = nil
		state.mouse_down_counter = 0
	elseif source == "mouse_move" then
		state.mouse_in_window = true

		local mouseX, mouseY = get_virt_mouse_pos()
		if
			user_opts.minmousemove == 0
			or (
				(state.last_mouseX ~= nil and state.last_mouseY ~= nil)
				and (
					(math.abs(mouseX - state.last_mouseX) >= user_opts.minmousemove)
					or (math.abs(mouseY - state.last_mouseY) >= user_opts.minmousemove)
				)
			)
		then
			if user_opts.bottomhover then -- if enabled, only show osc if mouse is hovering at the bottom of the screen (where the UI elements are)
				local top_hover = window_controls_enabled()
					and (user_opts.show_window_title or user_opts.window_controls)
				if
					mouseY > osc_param.playresy - (user_opts.bottomhover_zone or 130)
					or (
							(user_opts.window_top_bar == "yes" or not (state.border and state.title_bar))
							or state.fullscreen
						)
						and (mouseY < 40 and top_hover)
				then
					show_osc()
				else
					state.touchtime = nil

					if get_hidetimeout() >= 0 and get_touchtimeout() <= 0 then
						local elapsed_time = mp.get_time() - state.showtime

						if elapsed_time >= (get_hidetimeout() / 1000) then
							hide_osc()
						end
					end
				end
			else
				show_osc()
			end
		end
		state.last_mouseX, state.last_mouseY = mouseX, mouseY

		local n = state.active_element
		if element_has_action(elements[n], action) then
			elements[n].eventresponder[action](elements[n])
		end
	end

	-- ensure rendering after any (mouse) event - icons could change etc
	request_tick()
end

local function do_enable_keybindings()
	if state.enabled then
		if not state.showhide_enabled then
			mp.enable_key_bindings("showhide", "allow-vo-dragging+allow-hide-cursor")
			mp.enable_key_bindings("showhide_wc", "allow-vo-dragging+allow-hide-cursor")
		end
		state.showhide_enabled = true
	end
end

local function enable_osc(enable)
	state.enabled = enable
	if enable then
		do_enable_keybindings()
	else
		hide_osc() -- acts immediately when state.enabled == false
		if state.showhide_enabled then
			mp.disable_key_bindings("showhide")
			mp.disable_key_bindings("showhide_wc")
		end
		state.showhide_enabled = false
	end
end

local function render()
	msg.trace("rendering")
	local current_screen_sizeX, current_screen_sizeY = mp.get_osd_size()
	local mouseX, mouseY = get_virt_mouse_pos()
	local now = mp.get_time()

	-- check if display changed, if so request reinit
	if state.screen_sizeX ~= current_screen_sizeX or state.screen_sizeY ~= current_screen_sizeY then
		request_init_resize()

		state.screen_sizeX = current_screen_sizeX
		state.screen_sizeY = current_screen_sizeY
	end

	-- init management
	if state.active_element then
		-- mouse is held down on some element - keep ticking and ignore initReq
		-- till it's released, or else the mouse-up (click) will misbehave or
		-- get ignored. that's because osc_init() recreates the osc elements,
		-- but mouse handling depends on the elements staying unmodified
		-- between mouse-down and mouse-up (using the index active_element).
		request_tick()
	elseif state.initREQ then
		osc_init()
		state.initREQ = false

		-- store initial mouse position
		if (state.last_mouseX == nil or state.last_mouseY == nil) and not (mouseX == nil or mouseY == nil) then
			state.last_mouseX, state.last_mouseY = mouseX, mouseY
		end
	end

	-- fade animation
	if state.anitype ~= nil then
		if state.anistart == nil then
			state.anistart = now
		end

		if now < state.anistart + (user_opts.fadeduration / 1000) then
			if state.anitype == "in" then --fade in
				osc_visible(true)
				state.animation =
					scale_value(state.anistart, (state.anistart + (user_opts.fadeduration / 1000)), 255, 0, now)
			elseif state.anitype == "out" then --fade out
				state.animation =
					scale_value(state.anistart, (state.anistart + (user_opts.fadeduration / 1000)), 0, 255, now)
			end
		else
			if state.anitype == "out" then
				osc_visible(false)
			end
			kill_animation()
		end
	else
		kill_animation()
	end

	--mouse show/hide area
	for _, cords in pairs(osc_param.areas["showhide"]) do
		set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide")
	end
	if osc_param.areas["showhide_wc"] then
		for _, cords in pairs(osc_param.areas["showhide_wc"]) do
			set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide_wc")
		end
	else
		set_virt_mouse_area(0, 0, 0, 0, "showhide_wc")
	end
	do_enable_keybindings()

	--mouse input area
	local mouse_over_osc = false

	for _, cords in ipairs(osc_param.areas["input"]) do
		if state.osc_visible then -- activate only when OSC is actually visible
			set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "input")
		end
		if state.osc_visible ~= state.input_enabled then
			if state.osc_visible then
				mp.enable_key_bindings("input")
			else
				mp.disable_key_bindings("input")
			end
			state.input_enabled = state.osc_visible
		end

		if mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2) and user_opts.osc_keep_with_cursor then
			mouse_over_osc = true
		end
	end

	if osc_param.areas["window-controls"] then
		for _, cords in ipairs(osc_param.areas["window-controls"]) do
			if state.osc_visible then -- activate only when OSC is actually visible
				set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "window-controls")
				mp.enable_key_bindings("window-controls")
			else
				mp.disable_key_bindings("window-controls")
			end

			if mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2) and user_opts.osc_keep_with_cursor then
				mouse_over_osc = true
			end
		end
	end

	if osc_param.areas["window-controls-title"] then
		for _, cords in ipairs(osc_param.areas["window-controls-title"]) do
			if state.osc_visible then -- activate only when OSC is actually visible
				set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "window-controls-title")
			end
			if state.osc_visible ~= state.windowcontrols_title then
				if state.osc_visible then
					mp.enable_key_bindings("window-controls-title", "allow-vo-dragging")
				else
					mp.disable_key_bindings("window-controls-title")
				end
				state.windowcontrols_title = state.osc_visible
			end

			if mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2) and user_opts.osc_keep_with_cursor then
				mouse_over_osc = true
			end
		end
	end

	-- autohide
	if state.showtime ~= nil and get_hidetimeout() >= 0 then
		local timeout = state.showtime + (get_hidetimeout() / 1000) - now
		if timeout <= 0 and get_touchtimeout() <= 0 then
			if state.active_element == nil and not mouse_over_osc then
				hide_osc()
			end
		else
			-- the timer is only used to recheck the state and to possibly run
			-- the code above again
			if not state.hide_timer then
				state.hide_timer = mp.add_timeout(0, tick)
			end
			state.hide_timer.timeout = timeout
			-- re-arm
			state.hide_timer:kill()
			state.hide_timer:resume()
		end
	end

	-- actual rendering
	local ass = assdraw.ass_new()

	-- actual OSC
	if state.osc_visible then
		render_elements(ass)
	end

	if user_opts.persistentprogress or state.persistent_progress_toggle then
		render_persistentprogressbar(ass)
	end

	-- submit
	set_osd(osc_param.playresy * osc_param.display_aspect, osc_param.playresy, ass.text, 1000)
end

-- called by mpv on every frame
tick = function()
	if state.marginsREQ == true then
		update_margins()
		state.marginsREQ = false
	end

	if not state.enabled then
		return
	end

	if state.idle then
		-- render idle message
		msg.trace("idle message")
		local _, _, display_aspect = mp.get_osd_size()
		if display_aspect == 0 then
			return
		end
		local display_h = 360
		local display_w = display_h * display_aspect
		-- logo is rendered at 2^(6-1) = 32 times resolution with size 1800x1800
		local icon_x, icon_y = (display_w - 1800 / 32) / 2, 140
		local line_prefix = ("{\\rDefault\\an7\\1a&H00&\\bord0\\shad0\\pos(%f,%f)}"):format(icon_x, icon_y)

		local ass = assdraw.ass_new()
		-- mpv logo
		if user_opts.idlescreen then
			for _, line in ipairs(logo_lines) do
				ass:new_event()
				ass:append(line_prefix .. line)
			end
		end

		-- Santa hat
		if is_december and user_opts.idlescreen and not user_opts.greenandgrumpy then
			for _, line in ipairs(santa_hat_lines) do
				ass:new_event()
				ass:append(line_prefix .. line)
			end
		end

		if user_opts.idlescreen then
			ass:new_event()
			ass:pos(display_w / 2, icon_y + 65)
			ass:an(8)
			ass:append(locale.idle)
		end
		set_osd(display_w, display_h, ass.text, -1000)

		if state.showhide_enabled then
			mp.disable_key_bindings("showhide")
			mp.disable_key_bindings("showhide_wc")
			state.showhide_enabled = false
		end
	elseif (state.fullscreen and user_opts.showfullscreen) or (not state.fullscreen and user_opts.showwindowed) then
		-- render the OSC
		render()
	else
		-- Flush OSD
		render_wipe()
	end

	state.tick_last_time = mp.get_time()

	if state.anitype ~= nil then
		-- state.anistart can be nil - animation should now start, or it can
		-- be a timestamp when it started. state.idle has no animation.
		if
			not state.idle
			and (not state.anistart or mp.get_time() < 1 + state.anistart + user_opts.fadeduration / 1000)
		then
			-- animating or starting, or still within 1s past the deadline
			request_tick()
		else
			kill_animation()
		end
	end
end

-- duration is observed for the sole purpose of updating chapter markers
-- positions. live streams with chapters are very rare, and the update is also
-- expensive (with request_init), so it's only observed when we have chapters
-- and the user didn't disable the livemarkers option (update_duration_watch).
local function on_duration()
	request_init()
end

local duration_watched = false
local function update_duration_watch()
	local want_watch = user_opts.livemarkers and (mp.get_property_number("chapters", 0) or 0) > 0 and true or false -- ensure it's a boolean

	if want_watch ~= duration_watched then
		if want_watch then
			mp.observe_property("duration", "native", on_duration)
		else
			mp.unobserve_property(on_duration)
		end
		duration_watched = want_watch
	end
end

local function set_tick_delay(_, display_fps)
	-- may be nil if unavailable or 0 fps is reported
	if not display_fps or not user_opts.tick_delay_follow_display_fps then
		tick_delay = user_opts.tick_delay
		return
	end
	tick_delay = 1 / display_fps
end

mp.register_event("file-loaded", function()
	is_image() -- check if file is an image
	state.new_file_flag = true
	state.file_size_normalized = "Approximating size..."
	check_path_url()
	if user_opts.automatickeyframemode then
		if mp.get_property_number("duration", 0) > user_opts.automatickeyframelimit then
			user_opts.seekbarkeyframes = true
		else
			user_opts.seekbarkeyframes = false
		end
	end
	if user_opts.osc_on_start then
		show_osc()
	end
end)
mp.register_event("start-file", request_init)
mp.observe_property("track-list", "native", request_init)
mp.observe_property("playlist-count", "native", request_init)
mp.observe_property("playlist-pos", "native", request_init)
mp.observe_property("chapter-list", "native", function(_, list)
	list = list or {} -- safety, shouldn't return nil
	table.sort(list, function(a, b)
		return a.time < b.time
	end)
	state.chapter_list = list
	update_duration_watch()
	request_init()
end)
mp.observe_property("seeking", "native", function(_, seeking)
	if user_opts.seek_resets_hidetimeout then
		reset_timeout()
	end

	if state.new_file_flag then
		state.new_file_flag = false
		return
	end

	if seeking and user_opts.osc_on_seek then
		mp.register_event("seek", show_osc) -- show OSC while seeking
	else
		mp.unregister_event(show_osc) -- remove event when seeking stops
	end
end)
mp.observe_property("fullscreen", "bool", function(_, val)
	state.fullscreen = val
	state.marginsREQ = true
	adjust_subtitles(state.osc_visible)
	request_init_resize()
end)
mp.observe_property("border", "bool", function(_, val)
	state.border = val
	request_init_resize()
end)
mp.observe_property("title-bar", "bool", function(_, val)
	state.title_bar = val
	request_init_resize()
end)
mp.observe_property("window-maximized", "bool", function(_, val)
	state.maximized = val
	request_init_resize()
end)
mp.observe_property("idle-active", "bool", function(_, val)
	state.idle = val
	request_tick()
end)
mp.observe_property("display-fps", "number", set_tick_delay)
mp.observe_property("demuxer-cache-state", "native", cache_state)
mp.observe_property("vo-configured", "bool", request_tick)
mp.observe_property("playback-time", "number", request_tick)
mp.observe_property("osd-dimensions", "native", function()
	-- (we could use the value instead of re-querying it all the time, but then
	--  we might have to worry about property update ordering)
	request_init_resize()
	adjust_subtitles(state.osc_visible)
end)
mp.observe_property("osd-scale-by-window", "native", request_init_resize)
mp.observe_property("touch-pos", "native", handle_touch)
mp.observe_property("volume", "number", request_tick)
mp.observe_property("mute", "bool", function(_, val)
	state.mute = val
	request_tick()
end)
mp.observe_property("paused-for-cache", "bool", function(_, val)
	state.buffering = val
end)
-- ensure compatibility with auto looping scripts (eg: a script that sets videos under 2 seconds to loop by default)
mp.observe_property("loop-file", "string", function(_, val)
	state.looping = val ~= nil and val ~= "no"
end)
mp.observe_property("sub-pos", "native", function(_, value)
	if value == nil then
		return
	end

	if state.osc_adjusted_subpos == nil or value ~= state.osc_adjusted_subpos then
		state.user_subpos = value
	end
end)

-- mouse show/hide bindings
mp.set_key_bindings({
	{
		"mouse_move",
		function()
			process_event("mouse_move", nil)
		end,
	},
	{ "mouse_leave", mouse_leave },
}, "showhide", "force")
mp.set_key_bindings({
	{
		"mouse_move",
		function()
			process_event("mouse_move", nil)
		end,
	},
	{ "mouse_leave", mouse_leave },
}, "showhide_wc", "force")
do_enable_keybindings()

--mouse input bindings
mp.set_key_bindings({
	{
		"mbtn_left",
		function()
			process_event("mbtn_left", "up")
		end,
		function()
			process_event("mbtn_left", "down")
		end,
	},
	{
		"shift+mbtn_left",
		function()
			process_event("shift+mbtn_left", "up")
		end,
		function()
			process_event("shift+mbtn_left", "down")
		end,
	},
	{
		"mbtn_right",
		function()
			process_event("mbtn_right", "up")
		end,
		function()
			process_event("mbtn_right", "down")
		end,
	},
	{
		"shift+mbtn_right",
		function(e)
			process_event("shift+mbtn_right", "up")
		end,
		function(e)
			process_event("shift+mbtn_right", "down")
		end,
	},
	-- alias to shift_mbtn_left for single-handed mouse use
	{
		"mbtn_mid",
		function()
			process_event("shift+mbtn_left", "up")
		end,
		function()
			process_event("shift+mbtn_left", "down")
		end,
	},
	{
		"wheel_up",
		function()
			process_event("wheel_up", "press")
		end,
	},
	{
		"wheel_down",
		function()
			process_event("wheel_down", "press")
		end,
	},
	{ "mbtn_left_dbl", "ignore" },
	{ "shift+mbtn_left_dbl", "ignore" },
	{ "mbtn_right_dbl", "ignore" },
}, "input", "force")
mp.enable_key_bindings("input")

mp.set_key_bindings({
	{
		"mbtn_left",
		function()
			process_event("mbtn_left", "up")
		end,
		function()
			process_event("mbtn_left", "down")
		end,
	},
}, "window-controls", "force")
mp.enable_key_bindings("window-controls")

local function always_on(val)
	if state.enabled then
		if val then
			show_osc()
		else
			hide_osc()
		end
	end
end

-- mode can be auto/always/never/cycle
-- the modes only affect internal variables and not stored on its own.
local function visibility_mode(mode, no_osd)
	if mode == "cycle" then
		for i, allowed_mode in ipairs(state.visibility_modes) do
			if i == #state.visibility_modes then
				mode = state.visibility_modes[1]
				break
			elseif user_opts.visibility == allowed_mode then
				mode = state.visibility_modes[i + 1]
				break
			end
		end
	end

	if mode == "auto" then
		always_on(false)
		enable_osc(true)
	elseif mode == "always" then
		enable_osc(true)
		always_on(true)
	elseif mode == "never" then
		enable_osc(false)
	else
		msg.warn("Ignoring unknown visibility mode '" .. mode .. "'")
		return
	end

	user_opts.visibility = mode
	mp.set_property_native("user-data/osc/visibility", mode)

	if not no_osd and tonumber(mp.get_property("osd-level")) >= 1 then
		mp.osd_message("OSC visibility: " .. mode)
	end

	-- Reset the input state on a mode change. The input state will be
	-- recalculated on the next render cycle, except in 'never' mode where it
	-- will just stay disabled.
	mp.disable_key_bindings("input")
	mp.disable_key_bindings("window-controls")
	state.input_enabled = false

	update_margins()
	request_tick()
end

local function idlescreen_visibility(mode, no_osd)
	if mode == "cycle" then
		if user_opts.idlescreen then
			mode = "no"
		else
			mode = "yes"
		end
	end

	if mode == "yes" then
		user_opts.idlescreen = true
	else
		user_opts.idlescreen = false
	end

	mp.set_property_native("user-data/osc/idlescreen", user_opts.idlescreen)

	if not no_osd and tonumber(mp.get_property("osd-level")) >= 1 then
		mp.osd_message("OSC logo visibility: " .. tostring(mode))
	end

	request_tick()
end

mp.observe_property("pause", "bool", function(name, enabled)
	pause_state(name, enabled)
	if user_opts.showonpause and user_opts.visibility ~= "never" then
		state.enabled = enabled
		if enabled then
			-- save mode if a temporary change is needed
			if not state.temp_visibility_mode and user_opts.visibility ~= "always" then
				state.temp_visibility_mode = user_opts.visibility
			end

			if user_opts.keeponpause then
				-- set visibility to "always" temporarily
				visibility_mode("always", true)
			else
				show_osc()
			end
		else
			-- restore mode if it was changed temporarily
			if state.temp_visibility_mode then
				visibility_mode(state.temp_visibility_mode, true)
				state.temp_visibility_mode = nil
			else
				-- respect "always" mode on unpause
				visibility_mode(user_opts.visibility, true)
			end
		end
	end
end)

mp.register_script_message("osc-visibility", visibility_mode)
mp.register_script_message("osc-show", show_osc)
mp.register_script_message("osc-hide", function()
	if user_opts.visibility == "auto" then
		osc_visible(false)
	end
end)
mp.add_key_binding(nil, "visibility", function()
	visibility_mode("cycle")
end)
mp.add_key_binding(nil, "progress-toggle", function()
	user_opts.persistentprogress = not user_opts.persistentprogress
	state.persistent_progress_toggle = user_opts.persistentprogress
	request_init()
end)
mp.register_script_message("osc-idlescreen", idlescreen_visibility)
mp.register_script_message("thumbfast-info", function(json)
	local data = utils.parse_json(json)
	if type(data) ~= "table" or not data.width or not data.height then
		msg.error("thumbfast-info: received json didn't produce a table with thumbnail information")
	else
		thumbfast = data
	end
end)

-- validate string type user options
local function validate_user_opts()
	if
		user_opts.window_top_bar ~= "auto"
		and user_opts.window_top_bar ~= "yes"
		and user_opts.window_top_bar ~= "no"
	then
		msg.warn("window_top_bar cannot be '" .. user_opts.window_top_bar .. "'. Ignoring.")
		user_opts.window_top_bar = "auto"
	end

	if user_opts.seek_handle_size < 0 then
		msg.warn("seek_handle_size must be 0 or higher. Setting it to 0 (minimum).")
		user_opts.seek_handle_size = 0
	end

	if user_opts.volume_control_type ~= "linear" and user_opts.volume_control_type ~= "logarithmic" then
		msg.warn("volumecontrol cannot be '" .. user_opts.volume_control_type .. "'. Ignoring.")
		user_opts.volume_control_type = "linear"
	end

	if not language[user_opts.language] then
		msg.warn("language '" .. user_opts.language .. "' not found. Ignoring.")
		user_opts.language = "en"
		if not language["en"] then
			msg.warn("ERROR: can't find the default 'en' language or the one set by user_opts.")
		end
	end

	opt.read_options(user_opts, "colors")

	local colors = {
		user_opts.osc_color,
		user_opts.seekbarfg_color,
		user_opts.seekbarbg_color,
		user_opts.title_color,
		user_opts.time_color,
		user_opts.side_buttons_color,
		user_opts.middle_buttons_color,
		user_opts.playpause_color,
		user_opts.window_title_color,
		user_opts.window_controls_color,
		user_opts.held_element_color,
		user_opts.thumbnail_border_color,
		user_opts.chapter_title_color,
		user_opts.seekbar_cache_color,
		user_opts.hover_effect_color,
		user_opts.windowcontrols_close_hover,
		user_opts.windowcontrols_max_hover,
		user_opts.windowcontrols_min_hover,
		user_opts.cache_info_color,
		user_opts.thumbnail_border_outline,
	}

	for _, color in pairs(colors) do
		if color:find("^#%x%x%x%x%x%x$") == nil then
			msg.warn("'" .. color .. "' is not a valid color")
		end
	end

	for str in string.gmatch(user_opts.visibility_modes, "([^_]+)") do
		if str ~= "auto" and str ~= "always" and str ~= "never" then
			msg.warn("Ignoring unknown visibility mode '" .. str .. "' in list")
		else
			table.insert(state.visibility_modes, str)
		end
	end
end

-- read options from config and command-line
opt.read_options(user_opts, "modernz", function(changed)
	validate_user_opts()
	set_osc_locale()
	set_icon_theme()
	set_osc_styles()
	set_time_styles(changed.timetotal, changed.timems)
	if changed.tick_delay or changed.tick_delay_follow_display_fps then
		set_tick_delay("display_fps", mp.get_property_number("display_fps"))
	end
	request_tick()
	visibility_mode(user_opts.visibility, true)
	update_duration_watch()
	request_init()
end)

validate_user_opts()
set_osc_locale()
set_icon_theme()
set_osc_styles()
set_time_styles(true, true)
set_tick_delay("display_fps", mp.get_property_number("display_fps"))
visibility_mode(user_opts.visibility, true)
update_duration_watch()

set_virt_mouse_area(0, 0, 0, 0, "input")
set_virt_mouse_area(0, 0, 0, 0, "window-controls")
set_virt_mouse_area(0, 0, 0, 0, "window-controls-title")
