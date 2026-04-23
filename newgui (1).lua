--!nolint UnknownGlobal
--!nocheck

-- ──────────────────────────────────────────────────────────────
-- Unload previous instance (Utopia compat)
-- ──────────────────────────────────────────────────────────────
if getgenv().Library then
	getgenv().Library:Unload()
end

if not getgenv().cloneref then
	getgenv().cloneref = function(...) return ... end
end

-- ──────────────────────────────────────────────────────────────
-- Services
-- ──────────────────────────────────────────────────────────────
local Services = setmetatable({}, {
	__index = function(self, Name)
		local ok, result = pcall(game.FindService, game, Name)
		if ok and result then
			result = cloneref(result)
			rawset(self, Name, result)
			return result
		end
	end,
})

local TweenService    = Services.TweenService
local UserInputService = Services.UserInputService
local Players          = Services.Players
local RunService       = Services.RunService
local HttpService      = Services.HttpService
local CoreGui          = Services.CoreGui
local TextService      = Services.TextService

local LocalPlayer = Players.LocalPlayer
local Mouse       = LocalPlayer:GetMouse()

-- ──────────────────────────────────────────────────────────────
-- Library table  (Utopia-compatible surface)
-- ──────────────────────────────────────────────────────────────
local Library = {
	-- Utopia flag system
	Flags      = {},
	SetFlags   = {},
	IsLoading  = true,

	-- Utopia menu keybind (Insert by default, matches newgui)
	MenuKeybind = tostring(Enum.KeyCode.Insert),

	-- Utopia internals (used by GetConfig / LoadConfig)
	Connections        = {},
	Threads            = {},
	UnnamedConnections = 0,
	UnnamedFlags       = 0,
	OnUnloadCallbacks  = {},
	CurrentFrames      = {},

	-- Utopia hierarchy metatables
	Pages    = {},
	Sections = {},
}

Library.__index          = Library
Library.Pages.__index    = Library.Pages
Library.Sections.__index = Library.Sections

-- ──────────────────────────────────────────────────────────────
-- Utopia helper methods
-- ──────────────────────────────────────────────────────────────
function Library:NextFlag()
	self.UnnamedFlags = self.UnnamedFlags + 1
	return string.format("Flag_%d_%s", self.UnnamedFlags, HttpService:GenerateGUID(false))
end

function Library:SafeCall(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn(err) end
	return ok
end

function Library:Thread(fn)
	local t = coroutine.create(fn)
	coroutine.wrap(function() coroutine.resume(t) end)()
	table.insert(self.Threads, t)
	return t
end

function Library:Connect(event, callback)
	self.UnnamedConnections = self.UnnamedConnections + 1
	local conn = { Connection = nil }
	self:Thread(function()
		conn.Connection = event:Connect(function(...)
			if self.Unloaded then return end
			callback(...)
		end)
	end)
	table.insert(self.Connections, conn)
	return conn
end

function Library:OnUnload(cb)
	if type(cb) == "function" then table.insert(self.OnUnloadCallbacks, cb) end
end

function Library:Unload()
	self.Unloaded = true
	for _, cb in next, self.OnUnloadCallbacks do pcall(cb) end
	for _, c in self.Connections do
		if c.Connection then pcall(function() c.Connection:Disconnect() end) end
	end
	for _, t in self.Threads do pcall(coroutine.close, t) end
	if self._ScreenGui then pcall(function() self._ScreenGui:Destroy() end) end
	self.Flags = nil
	self.Connections = {}
	self.Threads = {}
	self.OnUnloadCallbacks = nil
	getgenv().Library = nil
end

function Library:GetConfig()
	local cfg = {}
	for flag, v in pairs(self.Flags) do
		if type(v) == "table" and v.Key then
			cfg[flag] = { Key = tostring(v.Key), Mode = v.Mode }
		elseif typeof(v) == "Color3" then
			cfg[flag] = { Color = v:ToHex() }
		else
			cfg[flag] = v
		end
	end
	return HttpService:JSONEncode(cfg)
end

function Library:LoadConfig(json)
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok then return end
	for flag, v in pairs(decoded) do
		local fn = self.SetFlags[flag]
		if not fn then continue end
		if type(v) == "table" and v.Key   then fn(v)
		elseif type(v) == "table" and v.Color then fn(Color3.fromHex(v.Color))
		else fn(v) end
	end
end

-- ──────────────────────────────────────────────────────────────
-- Original newgui helpers (kept exactly)
-- ──────────────────────────────────────────────────────────────
function Library:Tween(...)
	TweenService:Create(...):Play()
end

function Library:create(Object, Properties, Parent)
	local Obj = Instance.new(Object)
	for i, v in pairs(Properties) do
		Obj[i] = v
	end
	if Parent ~= nil then
		Obj.Parent = Parent
	end
	return Obj
end

function Library:get_text_size(...)
	return TextService:GetTextSize(...)
end

function Library:console(func)
	func(("\n"):rep(57))
end

function Library:set_draggable(gui)
	local dragging, dragInput, dragStart, startPos

	local function update(input)
		local delta = input.Position - dragStart
		gui.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end

	gui.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging  = true
			dragStart = input.Position
			startPos  = gui.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	gui.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			update(input)
		end
	end)
end

-- ──────────────────────────────────────────────────────────────
-- Signal (kept from newgui — used by OnLoad)
-- ──────────────────────────────────────────────────────────────
local Signal = {} do
	Signal.__index = Signal

	function Signal.new()
		return setmetatable({ _handlers = {} }, Signal)
	end

	function Signal:Connect(fn)
		table.insert(self._handlers, fn)
		return {
			Disconnect = function(self2)
				for i, h in ipairs(Signal._handlers or {}) do
					if h == fn then table.remove(Signal._handlers, i) break end
				end
			end
		}
	end

	function Signal:Fire(...)
		for _, fn in ipairs(self._handlers) do
			pcall(fn, ...)
		end
	end
end

Library.Signal = Signal

-- ──────────────────────────────────────────────────────────────
-- Library:Window  →  wraps Library.new internally
-- Returns a Window object with Utopia API
-- ──────────────────────────────────────────────────────────────
function Library:Window(Data)
	Data = Data or {}

	-- ── build the ScreenGui & all newgui chrome ──────────────
	local menu_title    = Data.Name or Data.name or "Window"
	local cfg_location  = Data.ConfigFolder or "LibraryConfigs/"

	-- ensure config folder exists
	if not isfolder(cfg_location) then
		pcall(makefolder, cfg_location)
	end

	-- OnLoad signal (used internally by element set_value on load)
	local OnLoad = Signal.new()

	local open = true

	-- ── ScreenGui ────────────────────────────────────────────
	local ScreenGui = Library:create("ScreenGui", {
		ResetOnSpawn   = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		Name           = "Library",
		IgnoreGuiInset = true,
	})
	ScreenGui.Parent = CoreGui
	Library._ScreenGui = ScreenGui

	-- Cursor
	local Cursor = Library:create("ImageLabel", {
		Name                = "Cursor",
		BackgroundTransparency = 1,
		Size                = UDim2.new(0, 17, 0, 17),
		Image               = "rbxassetid://7205257578",
		ZIndex              = 6969,
	}, ScreenGui)

	RunService.RenderStepped:Connect(function()
		if not Cursor or not Cursor.Parent then return end
		Cursor.Position = UDim2.new(0, Mouse.X, 0, Mouse.Y + 36)
	end)

	-- ── Main frame ───────────────────────────────────────────
	local ImageLabel = Library:create("ImageButton", {
		Name             = "Main",
		AnchorPoint      = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(15, 15, 15),
		BorderColor3     = Color3.fromRGB(78, 93, 234),
		Position         = UDim2.new(0.5, 0, 0.5, 0),
		Size             = Data.Size or UDim2.new(0, 700, 0, 500),
		Image            = "http://www.roblox.com/asset/?id=7300333488",
		AutoButtonColor  = false,
		Modal            = true,
	}, ScreenGui)

	Library:set_draggable(ImageLabel)

	-- Title
	Library:create("TextLabel", {
		Name               = "Title",
		AnchorPoint        = Vector2.new(0.5, 0),
		BackgroundColor3   = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		Position           = UDim2.new(0.5, 0, 0, 0),
		Size               = UDim2.new(1, -22, 0, 30),
		Font               = Enum.Font.Ubuntu,
		Text               = menu_title,
		TextColor3         = Color3.fromRGB(255, 255, 255),
		TextSize           = 16,
		TextXAlignment     = Enum.TextXAlignment.Left,
		RichText           = true,
	}, ImageLabel)

	-- Tab icon strip (left column)
	local TabButtons = Library:create("Frame", {
		Name               = "TabButtons",
		BackgroundColor3   = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		Position           = UDim2.new(0, 12, 0, 41),
		Size               = UDim2.new(0, 76, 0, 447),
	}, ImageLabel)

	Library:create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, TabButtons)

	-- Tab content area (right portion)
	local Tabs = Library:create("Frame", {
		Name               = "Tabs",
		BackgroundColor3   = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		Position           = UDim2.new(0, 102, 0, 42),
		Size               = UDim2.new(0, 586, 0, 446),
	}, ImageLabel)

	-- ── Toggle visibility (Utopia: MenuKeybind) ──────────────
	UserInputService.InputBegan:Connect(function(key, gp)
		if gp then return end
		if tostring(key.KeyCode) == Library.MenuKeybind
		or tostring(key.UserInputType) == Library.MenuKeybind then
			open = not open
			ScreenGui.Enabled = open
		end
	end)

	-- ── Window object (Utopia API) ───────────────────────────
	local Window = {
		IsOpen   = true,
		Pages    = {},
		Sections = {},
		Items    = { Root = ImageLabel },
	}

	function Window:SetOpen(bool)
		Window.IsOpen     = bool
		ScreenGui.Enabled = bool
		open              = bool
	end

	-- ── Tab management state ─────────────────────────────────
	local is_first_tab = true
	local selected_tab
	local tab_num = 0

	-- ──────────────────────────────────────────────────────────
	-- Window:Page  (Utopia API)
	-- Data.Icon = rbxassetid string (optional)
	-- Data.Name = page name shown in tab
	-- ──────────────────────────────────────────────────────────
	function Window:Page(Data2)
		Data2 = Data2 or {}

		tab_num = tab_num + 1
		local my_tab_num = tab_num

		-- ── Tab icon button ───────────────────────────────────
		local TabButton = Library:create("TextButton", {
			BackgroundColor3       = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			Size                   = UDim2.new(0, 76, 0, 90),
			Text                   = "",
		}, TabButtons)

		local tab_image = Data2.Icon or ""
		local TabImage = Library:create("ImageLabel", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position               = UDim2.new(0.5, 0, 0.45, 0),
			Size                   = UDim2.new(0, 32, 0, 32),
			Image                  = tab_image,
			ImageColor3            = Color3.fromRGB(100, 100, 100),
		}, TabButton)

		-- If no icon, show the page name as text inside the button
		local TabLabel
		if tab_image == "" then
			TabLabel = Library:create("TextLabel", {
				AnchorPoint            = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Position               = UDim2.new(0.5, 0, 0.5, 0),
				Size                   = UDim2.new(1, -4, 0, 32),
				Font                   = Enum.Font.Ubuntu,
				Text                   = Data2.Name or Data2.name or "",
				TextColor3             = Color3.fromRGB(100, 100, 100),
				TextSize               = 13,
				TextWrapped            = true,
			}, TabButton)
		end

		-- ── Tab frame ─────────────────────────────────────────
		local Tab = Library:create("Frame", {
			Name               = "Tab",
			BackgroundTransparency = 1,
			Size               = UDim2.new(1, 0, 1, 0),
			Visible            = false,
		}, Tabs)

		-- Section header strip (sub-pages within this tab)
		local TabSections = Library:create("Frame", {
			Name               = "TabSections",
			BackgroundTransparency = 1,
			Size               = UDim2.new(1, 0, 0, 28),
			ClipsDescendants   = true,
		}, Tab)

		Library:create("UIListLayout", {
			FillDirection       = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, TabSections)

		-- Section content frames
		local TabFrames = Library:create("Frame", {
			Name               = "TabFrames",
			BackgroundTransparency = 1,
			Position           = UDim2.new(0, 0, 0, 29),
			Size               = UDim2.new(1, 0, 0, 418),
		}, Tab)

		-- First tab is auto-selected
		if is_first_tab then
			is_first_tab = false
			selected_tab = TabButton
			TabImage.ImageColor3 = Color3.fromRGB(84, 101, 255)
			if TabLabel then TabLabel.TextColor3 = Color3.fromRGB(84, 101, 255) end
			Tab.Visible = true
		end

		-- Tab click
		TabButton.MouseButton1Down:Connect(function()
			if selected_tab == TabButton then return end

			-- Deactivate all tabs
			for _, child in ipairs(TabButtons:GetChildren()) do
				if child:IsA("TextButton") then
					local img = child:FindFirstChildWhichIsA("ImageLabel")
					if img then
						Library:Tween(img, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ ImageColor3 = Color3.fromRGB(100, 100, 100) })
					end
					local lbl = child:FindFirstChildWhichIsA("TextLabel")
					if lbl then
						Library:Tween(lbl, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ TextColor3 = Color3.fromRGB(100, 100, 100) })
					end
				end
			end
			for _, t in ipairs(Tabs:GetChildren()) do
				t.Visible = false
			end

			Tab.Visible = true
			selected_tab = TabButton

			Library:Tween(TabImage, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageColor3 = Color3.fromRGB(84, 101, 255) })
			if TabLabel then
				Library:Tween(TabLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextColor3 = Color3.fromRGB(84, 101, 255) })
			end
		end)

		TabButton.MouseEnter:Connect(function()
			if selected_tab == TabButton then return end
			Library:Tween(TabImage, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageColor3 = Color3.fromRGB(255, 255, 255) })
			if TabLabel then
				Library:Tween(TabLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextColor3 = Color3.fromRGB(255, 255, 255) })
			end
		end)

		TabButton.MouseLeave:Connect(function()
			if selected_tab == TabButton then return end
			Library:Tween(TabImage, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageColor3 = Color3.fromRGB(100, 100, 100) })
			if TabLabel then
				Library:Tween(TabLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextColor3 = Color3.fromRGB(100, 100, 100) })
			end
		end)

		-- ── Page object ───────────────────────────────────────
		local Page = {
			Window      = Window,
			ColumnsData = {},
			Items       = { Tab = Tab, TabSections = TabSections, TabFrames = TabFrames },
		}

		-- Section management state
		local is_first_section = true
		local num_sections     = 0
		local selected_section

		-- ──────────────────────────────────────────────────────
		-- Page:Section  (Utopia API)
		-- ──────────────────────────────────────────────────────
		function Page:Section(Data3)
			Data3 = Data3 or {}
			local section_name = Data3.Name or Data3.name or "Section"

			num_sections = num_sections + 1

			-- ── Section tab button ────────────────────────────
			local SectionButton = Library:create("TextButton", {
				Name               = "SectionButton",
				BackgroundTransparency = 1,
				Size               = UDim2.new(1 / num_sections, 0, 1, 0),
				Font               = Enum.Font.Ubuntu,
				Text               = section_name,
				TextColor3         = Color3.fromRGB(100, 100, 100),
				TextSize           = 15,
			}, TabSections)

			-- Resize all section buttons equally
			for _, sb in ipairs(TabSections:GetChildren()) do
				if sb:IsA("TextButton") then
					sb.Size = UDim2.new(1 / num_sections, 0, 1, 0)
				end
			end

			SectionButton.MouseEnter:Connect(function()
				if selected_section == SectionButton then return end
				Library:Tween(SectionButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextColor3 = Color3.fromRGB(255, 255, 255) })
			end)
			SectionButton.MouseLeave:Connect(function()
				if selected_section == SectionButton then return end
				Library:Tween(SectionButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextColor3 = Color3.fromRGB(100, 100, 100) })
			end)

			-- Underline decoration
			local SectionDecoration = Library:create("Frame", {
				Name             = "SectionDecoration",
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel  = 0,
				Position         = UDim2.new(0, 0, 0, 27),
				Size             = UDim2.new(1, 0, 0, 1),
				Visible          = false,
			}, SectionButton)

			Library:create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0,   Color3.fromRGB(32,  33,  38)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(81,  97, 243)),
					ColorSequenceKeypoint.new(1,   Color3.fromRGB(32,  33,  38)),
				}),
			}, SectionDecoration)

			-- ── Section content frame ─────────────────────────
			local SectionFrame = Library:create("Frame", {
				Name               = "SectionFrame",
				BackgroundTransparency = 1,
				Size               = UDim2.new(1, 0, 1, 0),
				Visible            = false,
			}, TabFrames)

			-- Left column
			local Left = Library:create("Frame", {
				Name               = "Left",
				BackgroundTransparency = 1,
				Position           = UDim2.new(0, 8, 0, 14),
				Size               = UDim2.new(0, 282, 0, 395),
			}, SectionFrame)

			Library:create("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, 12),
			}, Left)

			-- Right column
			local Right = Library:create("Frame", {
				Name               = "Right",
				BackgroundTransparency = 1,
				Position           = UDim2.new(0, 298, 0, 14),
				Size               = UDim2.new(0, 282, 0, 395),
			}, SectionFrame)

			Library:create("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, 12),
			}, Right)

			SectionButton.MouseButton1Down:Connect(function()
				for _, sb in ipairs(TabSections:GetChildren()) do
					if sb:IsA("TextButton") then
						Library:Tween(sb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ TextColor3 = Color3.fromRGB(100, 100, 100) })
						if sb:FindFirstChild("SectionDecoration") then
							sb.SectionDecoration.Visible = false
						end
					end
				end
				for _, sf in ipairs(TabFrames:GetChildren()) do
					if sf:IsA("Frame") then sf.Visible = false end
				end
				selected_section          = SectionButton
				SectionFrame.Visible      = true
				SectionDecoration.Visible = true
				Library:Tween(SectionButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextColor3 = Color3.fromRGB(84, 101, 255) })
			end)

			if is_first_section then
				is_first_section          = false
				selected_section          = SectionButton
				SectionButton.TextColor3  = Color3.fromRGB(84, 101, 255)
				SectionDecoration.Visible = true
				SectionFrame.Visible      = true
			end

			-- ── Section object ────────────────────────────────
			local Section = {
				Window  = Window,
				Page    = Page,
				Name    = section_name,
				Items   = { Content = Left, Left = Left, Right = Right },
			}

			-- Helper: resolve Side parameter to column frame
			local function column(side)
				-- Side = 1 or "Left" → Left; Side = 2 or "Right" → Right
				if side == 2 or side == "Right" then return Right end
				return Left
			end

			-- ──────────────────────────────────────────────────
			-- Internal element factory (newgui's sector.element)
			-- Kept verbatim except:
			--   Library.Flags[flag]    replaces Menu.Values[...][flag]
			--   Library.SetFlags[flag] added per element
			-- ──────────────────────────────────────────────────
			local function make_element(col, etype, text, data, callback, c_flag)
				text     = text     or etype
				data     = data     or {}
				callback = callback or function() end

				local value = {}
				local flag  = c_flag and (text .. " " .. c_flag) or text

				Library.Flags[flag] = value

				local function do_callback()
					Library.Flags[flag] = value
					callback(value)
				end

				local default = data.default

				local element = {}
				function element:get_value() return value end

				-- ────────────────── Toggle ─────────────────────
				if etype == "Toggle" then
					local Border = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(5, 5, 5),
						BorderColor3     = Color3.fromRGB(30, 30, 30),
						Size             = UDim2.new(1, 0, 0, 18),
					}, col)

					local Container = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, Border)

					value = { Toggle = default and default.Toggle or false }

					local ToggleButton = Library:create("TextButton", {
						BackgroundColor3       = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 1,
						Size                   = UDim2.new(1, 0, 0, 18),
						Text                   = "",
					}, Container)

					function element:set_visible(bool)
						if bool then
							if ToggleButton.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, 18)
							ToggleButton.Visible = true
						else
							if not ToggleButton.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, -18)
							ToggleButton.Visible = false
						end
					end

					local ToggleFrame = Library:create("Frame", {
						AnchorPoint      = Vector2.new(0, 0.5),
						BackgroundColor3 = Color3.fromRGB(30, 30, 30),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 9, 0.5, 0),
						Size             = UDim2.new(0, 9, 0, 9),
					}, ToggleButton)

					local ToggleText = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Position       = UDim2.new(0, 27, 0, 5),
						Size           = UDim2.new(0, 200, 0, 9),
						Font           = Enum.Font.Ubuntu,
						Text           = text,
						TextColor3     = Color3.fromRGB(150, 150, 150),
						TextSize       = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
					}, ToggleButton)

					local mouse_in = false

					function element:set_value(new_value, cb)
						value = new_value and new_value or value
						Library.Flags[flag] = value

						if value.Toggle then
							Library:Tween(ToggleFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ BackgroundColor3 = Color3.fromRGB(84, 101, 255) })
							Library:Tween(ToggleText,  TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ TextColor3 = Color3.fromRGB(255, 255, 255) })
						else
							Library:Tween(ToggleFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ BackgroundColor3 = Color3.fromRGB(30, 30, 30) })
							if not mouse_in then
								Library:Tween(ToggleText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
									{ TextColor3 = Color3.fromRGB(150, 150, 150) })
							end
						end

						if cb == nil or not cb then do_callback() end
					end

					ToggleButton.MouseEnter:Connect(function()
						mouse_in = true
						if not value.Toggle then
							Library:Tween(ToggleText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ TextColor3 = Color3.fromRGB(255, 255, 255) })
						end
					end)
					ToggleButton.MouseLeave:Connect(function()
						mouse_in = false
						if not value.Toggle then
							Library:Tween(ToggleText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ TextColor3 = Color3.fromRGB(150, 150, 150) })
						end
					end)
					ToggleButton.MouseButton1Down:Connect(function()
						element:set_value({ Toggle = not value.Toggle })
					end)

					element:set_value(value, true)

					Library.SetFlags[flag] = function(v)
						-- v can be raw bool or {Toggle=bool}
						if type(v) == "boolean" then
							element:set_value({ Toggle = v })
						elseif type(v) == "table" then
							element:set_value(v)
						end
					end

					-- ── add_keybind (Utopia: Toggle:Keybind) ──
					local has_extra = false
					function element:add_keybind(key_default, key_callback)
						local keybind = {}
						if has_extra then return end
						has_extra = true
						local extra_flag = "$" .. flag

						local extra_value = { Key = nil, Type = "Always", Active = true }
						key_callback = key_callback or function() end

						Library.Flags[extra_flag] = extra_value

						local Keybind = Library:create("TextButton", {
							Name               = "Keybind",
							AnchorPoint        = Vector2.new(1, 0),
							BackgroundTransparency = 1,
							Position           = UDim2.new(0, 265, 0, 0),
							Size               = UDim2.new(0, 56, 0, 20),
							Font               = Enum.Font.Ubuntu,
							Text               = "[ NONE ]",
							TextColor3         = Color3.fromRGB(150, 150, 150),
							TextSize           = 14,
							TextXAlignment     = Enum.TextXAlignment.Right,
						}, ToggleButton)

						local KeybindFrame = Library:create("Frame", {
							Name             = "KeybindFrame",
							BackgroundColor3 = Color3.fromRGB(10, 10, 10),
							BorderColor3     = Color3.fromRGB(30, 30, 30),
							Position         = UDim2.new(1, 5, 0, 3),
							Size             = UDim2.new(0, 55, 0, 75),
							Visible          = false,
							ZIndex           = 2,
						}, Keybind)

						Library:create("UIListLayout", {
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							SortOrder           = Enum.SortOrder.LayoutOrder,
						}, KeybindFrame)

						local keybind_in  = false
						local keybind_in2 = false

						Keybind.MouseEnter:Connect(function()
							keybind_in = true
							Library:Tween(Keybind, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ TextColor3 = Color3.fromRGB(255, 255, 255) })
						end)
						Keybind.MouseLeave:Connect(function()
							keybind_in = false
							Library:Tween(Keybind, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ TextColor3 = Color3.fromRGB(150, 150, 150) })
						end)
						KeybindFrame.MouseEnter:Connect(function()
							keybind_in2 = true
							Library:Tween(KeybindFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ BorderColor3 = Color3.fromRGB(84, 101, 255) })
						end)
						KeybindFrame.MouseLeave:Connect(function()
							keybind_in2 = false
							Library:Tween(KeybindFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ BorderColor3 = Color3.fromRGB(30, 30, 30) })
						end)

						-- Close popup when clicking outside
						UserInputService.InputBegan:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseButton1
							or (input.UserInputType == Enum.UserInputType.MouseButton2 and not is_binding) then
								if KeybindFrame.Visible == true and not keybind_in and not keybind_in2 then
									KeybindFrame.Visible = false
								end
							end
						end)

						-- Type buttons: Always / Hold / Toggle
						local Always = Library:create("TextButton", {
							BackgroundTransparency = 1,
							Size       = UDim2.new(1, 0, 0, 25),
							Font       = Enum.Font.Ubuntu,
							Text       = "Always",
							TextColor3 = Color3.fromRGB(84, 101, 255),
							TextSize   = 14,
							ZIndex     = 2,
						}, KeybindFrame)

						local Hold = Library:create("TextButton", {
							BackgroundTransparency = 1,
							Size       = UDim2.new(1, 0, 0, 25),
							Font       = Enum.Font.Ubuntu,
							Text       = "Hold",
							TextColor3 = Color3.fromRGB(150, 150, 150),
							TextSize   = 14,
							ZIndex     = 2,
						}, KeybindFrame)

						local Toggle_btn = Library:create("TextButton", {
							BackgroundTransparency = 1,
							Size       = UDim2.new(1, 0, 0, 25),
							Font       = Enum.Font.Ubuntu,
							Text       = "Toggle",
							TextColor3 = Color3.fromRGB(150, 150, 150),
							TextSize   = 14,
							ZIndex     = 2,
						}, KeybindFrame)

						for _, TypeButton in next, KeybindFrame:GetChildren() do
							if TypeButton:IsA("UIListLayout") then continue end

							TypeButton.MouseEnter:Connect(function()
								if extra_value.Type ~= TypeButton.Text then
									Library:Tween(TypeButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
										{ TextColor3 = Color3.fromRGB(255, 255, 255) })
								end
							end)
							TypeButton.MouseLeave:Connect(function()
								if extra_value.Type ~= TypeButton.Text then
									Library:Tween(TypeButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
										{ TextColor3 = Color3.fromRGB(150, 150, 150) })
								end
							end)
							TypeButton.MouseButton1Down:Connect(function()
								KeybindFrame.Visible = false

								extra_value.Type = TypeButton.Text
								extra_value.Active = true

								key_callback(extra_value)
								Library.Flags[extra_flag] = extra_value

								for _, TypeButton2 in next, KeybindFrame:GetChildren() do
									if TypeButton2:IsA("UIListLayout") then continue end
									Library:Tween(TypeButton2, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
										{ TextColor3 = Color3.fromRGB(150, 150, 150) })
								end
								Library:Tween(TypeButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
									{ TextColor3 = Color3.fromRGB(84, 101, 255) })
							end)
						end

						local is_binding = false

						UserInputService.InputBegan:Connect(function(input)
							if is_binding then
								is_binding = false

								local new_value = input.KeyCode.Name ~= "Unknown" and input.KeyCode.Name
									or input.UserInputType.Name
								Keybind.Text = "[ " .. new_value:upper() .. " ]"
								Keybind.Size = UDim2.new(0,
									Library:get_text_size(Keybind.Text, 14, Enum.Font.Ubuntu, Vector2.new(700, 20)).X + 3,
									0, 20)
								extra_value.Key = new_value

								if new_value == "Backspace" then
									Keybind.Text = "[ NONE ]"
									Keybind.Size = UDim2.new(0,
										Library:get_text_size("[ NONE ]", 14, Enum.Font.Ubuntu, Vector2.new(700, 20)).X + 3,
										0, 20)
									extra_value.Key = nil
								end

								key_callback(extra_value)
								Library.Flags[extra_flag] = extra_value

							elseif extra_value.Key ~= nil then
								local key = input.KeyCode.Name ~= "Unknown" and input.KeyCode.Name
									or input.UserInputType.Name
								if key == extra_value.Key then
									if extra_value.Type == "Toggle" then
										extra_value.Active = not extra_value.Active
									elseif extra_value.Type == "Hold" then
										extra_value.Active = true
									end
									key_callback(extra_value)
									Library.Flags[extra_flag] = extra_value
								end
							end
						end)

						UserInputService.InputEnded:Connect(function(input)
							if extra_value.Key ~= nil and not is_binding then
								local key = input.KeyCode.Name ~= "Unknown" and input.KeyCode.Name
									or input.UserInputType.Name
								if key == extra_value.Key then
									if extra_value.Type == "Hold" then
										extra_value.Active = false
										key_callback(extra_value)
										Library.Flags[extra_flag] = extra_value
									end
								end
							end
						end)

						Keybind.MouseButton1Down:Connect(function()
							if not is_binding then
								wait()
								is_binding   = true
								Keybind.Text = "[ ... ]"
								Keybind.Size = UDim2.new(0,
									Library:get_text_size("[ ... ]", 14, Enum.Font.Ubuntu, Vector2.new(700, 20)).X + 3,
									0, 20)
							end
						end)

						Keybind.MouseButton2Down:Connect(function()
							if not is_binding then
								KeybindFrame.Visible = not KeybindFrame.Visible
							end
						end)

						function keybind:set_value(new_value, cb)
							extra_value = new_value and new_value or extra_value
							Library.Flags[extra_flag] = extra_value

							for _, TypeButton2 in next, KeybindFrame:GetChildren() do
								if TypeButton2:IsA("UIListLayout") then continue end
								if TypeButton2.Name ~= extra_value.Type then
									Library:Tween(TypeButton2, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
										{ TextColor3 = Color3.fromRGB(150, 150, 150) })
								else
									Library:Tween(TypeButton2, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
										{ TextColor3 = Color3.fromRGB(84, 101, 255) })
								end
							end

							local key_text = extra_value.Key ~= nil and extra_value.Key or "NONE"
							Keybind.Text = "[ " .. key_text:upper() .. " ]"
							Keybind.Size = UDim2.new(0,
								Library:get_text_size(Keybind.Text, 14, Enum.Font.Ubuntu, Vector2.new(700, 20)).X + 3,
								0, 20)

							if cb == nil or not cb then
								key_callback(extra_value)
							end
						end

						Library.SetFlags[extra_flag] = function(v) keybind:set_value(v) end

						-- Set default
						if key_default then
							keybind:set_value(key_default, true)
						end

						OnLoad:Connect(function()
							keybind:set_value(Library.Flags[extra_flag])
						end)

						return keybind
					end

					-- ── add_color (Utopia: Toggle:Colorpicker) ─
					function element:add_color(color_default, has_transparency, color_callback)
						if has_extra then return end
						has_extra = true

						local color = {}
						local extra_flag = "$" .. flag

						local extra_value = { Color = nil }
						color_callback = color_callback or function() end

						Library.Flags[extra_flag] = extra_value

						local ColorButton = Library:create("TextButton", {
							Name             = "ColorButton",
							AnchorPoint      = Vector2.new(1, 0.5),
							BackgroundColor3 = Color3.fromRGB(255, 28, 28),
							BorderColor3     = Color3.fromRGB(0, 0, 0),
							Position         = UDim2.new(0, 265, 0.5, 0),
							Size             = UDim2.new(0, 35, 0, 11),
							AutoButtonColor  = false,
							Font             = Enum.Font.Ubuntu,
							Text             = "",
							TextXAlignment   = Enum.TextXAlignment.Right,
						}, ToggleButton)

						local ColorFrame = Library:create("Frame", {
							Name             = "ColorFrame",
							BackgroundColor3 = Color3.fromRGB(10, 10, 10),
							BorderColor3     = Color3.fromRGB(0, 0, 0),
							Position         = UDim2.new(1, 5, 0, 0),
							Size             = UDim2.new(0, 200, 0, 170),
							Visible          = false,
							ZIndex           = 2,
						}, ColorButton)

						local ColorPicker = Library:create("ImageButton", {
							Name             = "ColorPicker",
							BackgroundColor3 = Color3.fromRGB(255, 255, 255),
							BorderColor3     = Color3.fromRGB(0, 0, 0),
							Position         = UDim2.new(0, 40, 0, 10),
							Size             = UDim2.new(0, 150, 0, 150),
							AutoButtonColor  = false,
							Image            = "rbxassetid://4155801252",
							ImageColor3      = Color3.fromRGB(255, 0, 4),
							ZIndex           = 2,
						}, ColorFrame)

						local ColorPick = Library:create("Frame", {
							Name             = "ColorPick",
							BackgroundColor3 = Color3.fromRGB(255, 255, 255),
							BorderColor3     = Color3.fromRGB(0, 0, 0),
							Size             = UDim2.new(0, 1, 0, 1),
							ZIndex           = 2,
						}, ColorPicker)

						local HuePicker = Library:create("TextButton", {
							Name             = "HuePicker",
							BackgroundColor3 = Color3.fromRGB(255, 255, 255),
							BorderColor3     = Color3.fromRGB(0, 0, 0),
							Position         = UDim2.new(0, 10, 0, 10),
							Size             = UDim2.new(0, 20, 0, 150),
							ZIndex           = 2,
							AutoButtonColor  = false,
							Text             = "",
						}, ColorFrame)

						Library:create("UIGradient", {
							Rotation = 90,
							Color = ColorSequence.new({
								ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0,   0)),
								ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 0, 255)),
								ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0,   0, 255)),
								ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
								ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 255,   0)),
								ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 255,   0)),
								ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0,   0)),
							}),
						}, HuePicker)

						local HuePick = Library:create("ImageButton", {
							Name             = "HuePick",
							BackgroundColor3 = Color3.fromRGB(255, 255, 255),
							BorderColor3     = Color3.fromRGB(0, 0, 0),
							Size             = UDim2.new(1, 0, 0, 1),
							ZIndex           = 2,
						}, HuePicker)

						local in_color  = false
						local in_color2 = false

						ColorButton.MouseButton1Down:Connect(function()
							ColorFrame.Visible = not ColorFrame.Visible
						end)
						ColorFrame.MouseEnter:Connect(function()
							in_color = true
							Library:Tween(ColorFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ BorderColor3 = Color3.fromRGB(84, 101, 255) })
						end)
						ColorFrame.MouseLeave:Connect(function()
							in_color = false
							Library:Tween(ColorFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ BorderColor3 = Color3.fromRGB(0, 0, 0) })
						end)
						ColorButton.MouseEnter:Connect(function() in_color2 = true  end)
						ColorButton.MouseLeave:Connect(function() in_color2 = false end)
						UserInputService.InputBegan:Connect(function(input)
							if input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.MouseButton2 then
								if ColorFrame.Visible and not in_color and not in_color2 then
									ColorFrame.Visible = false
								end
							end
						end)

						-- Transparency slider (optional)
						local TransparencyColor, TransparencyPick
						if has_transparency then
							ColorFrame.Size = UDim2.new(0, 200, 0, 200)

							local TransparencyPicker = Library:create("ImageButton", {
								Name             = "TransparencyPicker",
								BackgroundColor3 = Color3.fromRGB(255, 255, 255),
								BorderColor3     = Color3.fromRGB(0, 0, 0),
								Position         = UDim2.new(0, 10, 0, 170),
								Size             = UDim2.new(0, 180, 0, 20),
								Image            = "rbxassetid://3887014957",
								ScaleType        = Enum.ScaleType.Tile,
								TileSize         = UDim2.new(0, 10, 0, 10),
								ZIndex           = 2,
							}, ColorFrame)

							TransparencyColor = Library:create("ImageLabel", {
								BackgroundTransparency = 1,
								Size  = UDim2.new(1, 0, 1, 0),
								Image = "rbxassetid://3887017050",
								ZIndex = 2,
							}, TransparencyPicker)

							TransparencyPick = Library:create("Frame", {
								Name             = "TransparencyPick",
								BackgroundColor3 = Color3.fromRGB(255, 255, 255),
								BorderColor3     = Color3.fromRGB(0, 0, 0),
								Size             = UDim2.new(0, 1, 1, 0),
								ZIndex           = 2,
							}, TransparencyPicker)

							extra_value.Transparency = 0

							function color.update_transp()
								local x = math.clamp(Mouse.X - TransparencyPicker.AbsolutePosition.X, 0, 180)
								TransparencyPick.Position = UDim2.new(0, x, 0, 0)
								extra_value.Transparency  = x / 180
								color_callback(extra_value)
								Library.Flags[extra_flag] = extra_value
							end

							TransparencyPicker.MouseButton1Down:Connect(function()
								color.update_transp()
								local mc = Mouse.Move:Connect(function() color.update_transp() end)
								local rc; rc = UserInputService.InputEnded:Connect(function(m)
									if m.UserInputType == Enum.UserInputType.MouseButton1 then
										color.update_transp(); mc:Disconnect(); rc:Disconnect()
									end
								end)
							end)
						end

						-- HSV state
						color.h = 0; color.s = 1; color.v = 1

						extra_value.Color = Color3.fromHSV(color.h, color.s, color.v)
						Library.Flags[extra_flag] = extra_value

						function color.update_color()
							local cx = math.clamp(Mouse.X - ColorPicker.AbsolutePosition.X, 0, ColorPicker.AbsoluteSize.X)
								/ ColorPicker.AbsoluteSize.X
							local cy = math.clamp(Mouse.Y - ColorPicker.AbsolutePosition.Y, 0, ColorPicker.AbsoluteSize.Y)
								/ ColorPicker.AbsoluteSize.Y
							ColorPick.Position = UDim2.new(cx, 0, cy, 0)
							color.s = 1 - cx
							color.v = 1 - cy
							ColorButton.BackgroundColor3 = Color3.fromHSV(color.h, color.s, color.v)
							extra_value.Color            = Color3.fromHSV(color.h, color.s, color.v)
							color_callback(extra_value)
							Library.Flags[extra_flag] = extra_value
						end

						ColorPicker.MouseButton1Down:Connect(function()
							color.update_color()
							local mc = Mouse.Move:Connect(function() color.update_color() end)
							local rc; rc = UserInputService.InputEnded:Connect(function(m)
								if m.UserInputType == Enum.UserInputType.MouseButton1 then
									color.update_color(); mc:Disconnect(); rc:Disconnect()
								end
							end)
						end)

						function color.update_hue()
							local y = math.clamp(Mouse.Y - HuePicker.AbsolutePosition.Y, 0, 148)
							HuePick.Position = UDim2.new(0, 0, 0, y)
							color.h = 1 - y / 148
							ColorPicker.ImageColor3      = Color3.fromHSV(color.h, 1, 1)
							ColorButton.BackgroundColor3 = Color3.fromHSV(color.h, color.s, color.v)
							if TransparencyColor then
								TransparencyColor.ImageColor3 = Color3.fromHSV(color.h, 1, 1)
							end
							extra_value.Color = Color3.fromHSV(color.h, color.s, color.v)
							color_callback(extra_value)
							Library.Flags[extra_flag] = extra_value
						end

						HuePicker.MouseButton1Down:Connect(function()
							color.update_hue()
							local mc = Mouse.Move:Connect(function() color.update_hue() end)
							local rc; rc = UserInputService.InputEnded:Connect(function(m)
								if m.UserInputType == Enum.UserInputType.MouseButton1 then
									color.update_hue(); mc:Disconnect(); rc:Disconnect()
								end
							end)
						end)

						function color:set_value(new_value, cb)
							extra_value = new_value and new_value or extra_value
							Library.Flags[extra_flag] = extra_value

							local dup = Color3.new(extra_value.Color.R, extra_value.Color.G, extra_value.Color.B)
							color.h, color.s, color.v = dup:ToHSV()
							color.h = math.clamp(color.h, 0, 1)
							color.s = math.clamp(color.s, 0, 1)
							color.v = math.clamp(color.v, 0, 1)

							ColorPick.Position           = UDim2.new(1 - color.s, 0, 1 - color.v, 0)
							ColorPicker.ImageColor3      = Color3.fromHSV(color.h, 1, 1)
							ColorButton.BackgroundColor3 = Color3.fromHSV(color.h, color.s, color.v)
							HuePick.Position             = UDim2.new(0, 0, 1 - color.h, -1)

							if TransparencyColor then
								TransparencyColor.ImageColor3 = Color3.fromHSV(color.h, 1, 1)
								if TransparencyPick then
									TransparencyPick.Position = UDim2.new(extra_value.Transparency or 0, -1, 0, 0)
								end
							end

							if cb == nil or not cb then color_callback(extra_value) end
						end

						Library.SetFlags[extra_flag] = function(v) color:set_value(v) end

						if color_default then color:set_value(color_default, true) end

						OnLoad:Connect(function()
							color:set_value(Library.Flags[extra_flag])
						end)

						return color
					end

				-- ───────────────── Dropdown ────────────────────
				elseif etype == "Dropdown" then
					local Border = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(5, 5, 5),
						BorderColor3     = Color3.fromRGB(30, 30, 30),
						Size             = UDim2.new(1, 0, 0, 45),
					}, col)

					local Container = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, Border)

					value = { Dropdown = default and default.Dropdown or (data.options and data.options[1] or "") }

					local Dropdown = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 45),
						Text = "",
					}, Container)

					function element:set_visible(bool)
						if bool then
							if Dropdown.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, 45)
							Dropdown.Visible = true
						else
							if not Dropdown.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, -45)
							Dropdown.Visible = false
						end
					end

					local DropdownButton = Library:create("TextButton", {
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 9, 0, 20),
						Size             = UDim2.new(0, 260, 0, 20),
						AutoButtonColor  = false,
						Text             = "",
					}, Dropdown)

					local DropdownButtonText = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Position       = UDim2.new(0, 6, 0, 0),
						Size           = UDim2.new(0, 250, 1, 0),
						Font           = Enum.Font.Ubuntu,
						Text           = value.Dropdown,
						TextColor3     = Color3.fromRGB(150, 150, 150),
						TextSize       = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
					}, DropdownButton)

					Library:create("ImageLabel", {
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 245, 0, 8),
						Size     = UDim2.new(0, 6, 0, 4),
						Image    = "rbxassetid://6724771531",
					}, DropdownButton)

					local DropdownText = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Position       = UDim2.new(0, 9, 0, 6),
						Size           = UDim2.new(0, 200, 0, 9),
						Font           = Enum.Font.Ubuntu,
						Text           = text,
						TextColor3     = Color3.fromRGB(150, 150, 150),
						TextSize       = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
					}, Dropdown)

					local options_num = data.options and #data.options or 0
					local scrollSize  = options_num >= 4 and 80 or (20 * options_num)

					local DropdownScroll = Library:create("ScrollingFrame", {
						Active           = true,
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 9, 0, 41),
						Size             = UDim2.new(0, 260, 0, scrollSize),
						CanvasSize       = UDim2.new(0, 0, 0, 0),
						ScrollBarThickness = 2,
						TopImage         = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						BottomImage      = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						Visible          = false,
						ZIndex           = 2,
					}, Dropdown)

					if options_num >= 4 then
						for _ = 1, options_num do
							DropdownScroll.CanvasSize = DropdownScroll.CanvasSize + UDim2.new(0, 0, 0, 20)
						end
					end

					Library:create("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder           = Enum.SortOrder.LayoutOrder,
					}, DropdownScroll)

					local in_drop  = false
					local in_drop2 = false
					local dropdown_open = false

					DropdownButton.MouseButton1Down:Connect(function()
						DropdownScroll.Visible = not DropdownScroll.Visible
						dropdown_open = DropdownScroll.Visible
						local col3 = dropdown_open and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 150)
						Library:Tween(DropdownText,       TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = col3 })
						Library:Tween(DropdownButtonText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = col3 })
					end)
					Dropdown.MouseEnter:Connect(function()       in_drop  = true  end)
					Dropdown.MouseLeave:Connect(function()       in_drop  = false end)
					DropdownScroll.MouseEnter:Connect(function() in_drop2 = true  end)
					DropdownScroll.MouseLeave:Connect(function() in_drop2 = false end)
					UserInputService.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.MouseButton2 then
							if DropdownScroll.Visible and not in_drop and not in_drop2 then
								DropdownScroll.Visible = false
								DropdownScroll.CanvasPosition = Vector2.new(0, 0)
								Library:Tween(DropdownText,       TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								Library:Tween(DropdownButtonText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
							end
						end
					end)

					function element:set_value(new_value, cb)
						value = new_value and new_value or value
						Library.Flags[flag] = value
						DropdownButtonText.Text = new_value and new_value.Dropdown or (value.Dropdown or "")
						if cb == nil or not cb then do_callback() end
					end

					Library.SetFlags[flag] = function(v)
						if type(v) == "string" then element:set_value({ Dropdown = v })
						else element:set_value(v) end
					end

					if data.options then
						for _, v in next, data.options do
							local Btn = Library:create("TextButton", {
								Name             = v,
								BackgroundColor3 = Color3.fromRGB(25, 25, 25),
								BorderColor3     = Color3.fromRGB(0, 0, 0),
								BorderSizePixel  = 0,
								Size             = UDim2.new(1, 0, 0, 20),
								AutoButtonColor  = false,
								Font             = Enum.Font.SourceSans,
								Text             = "",
								ZIndex           = 2,
							}, DropdownScroll)

							local BtnText = Library:create("TextLabel", {
								BackgroundTransparency = 1,
								Position       = UDim2.new(0, 8, 0, 0),
								Size           = UDim2.new(0, 245, 1, 0),
								Font           = Enum.Font.Ubuntu,
								Text           = v,
								TextColor3     = Color3.fromRGB(150, 150, 150),
								TextSize       = 14,
								TextXAlignment = Enum.TextXAlignment.Left,
								ZIndex         = 2,
							}, Btn)

							local Deco = Library:create("Frame", {
								Name             = "Decoration",
								BackgroundColor3 = Color3.fromRGB(84, 101, 255),
								BorderSizePixel  = 0,
								Size             = UDim2.new(0, 1, 1, 0),
								Visible          = false,
								ZIndex           = 2,
							}, Btn)

							Btn.MouseEnter:Connect(function()
								Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) })
								Deco.Visible = true
							end)
							Btn.MouseLeave:Connect(function()
								Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								Deco.Visible = false
							end)
							Btn.MouseButton1Down:Connect(function()
								DropdownScroll.Visible = false
								DropdownButtonText.Text = v
								value.Dropdown = v
								Library:Tween(DropdownText,       TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								Library:Tween(DropdownButtonText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								Library.Flags[flag] = value
								do_callback()
							end)
						end
					end

					element:set_value(value, true)

				-- ──────────────────── Combo ────────────────────
				elseif etype == "Combo" then
					local Border = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(5, 5, 5),
						BorderColor3     = Color3.fromRGB(30, 30, 30),
						Size             = UDim2.new(1, 0, 0, 45),
					}, col)

					local Container = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, Border)

					value = { Combo = default and default.Combo or {} }

					local Dropdown = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 45),
						Text = "",
					}, Container)

					function element:set_visible(bool)
						if bool then
							if Dropdown.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, 45)
							Dropdown.Visible = true
						else
							if not Dropdown.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, -45)
							Dropdown.Visible = false
						end
					end

					local DropdownButton = Library:create("TextButton", {
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 9, 0, 20),
						Size             = UDim2.new(0, 260, 0, 20),
						AutoButtonColor  = false,
						Text             = "",
					}, Dropdown)

					local DropdownButtonText = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Position       = UDim2.new(0, 6, 0, 0),
						Size           = UDim2.new(0, 250, 1, 0),
						Font           = Enum.Font.Ubuntu,
						Text           = "...",
						TextColor3     = Color3.fromRGB(150, 150, 150),
						TextSize       = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
					}, DropdownButton)

					Library:create("ImageLabel", {
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 245, 0, 8),
						Size     = UDim2.new(0, 6, 0, 4),
						Image    = "rbxassetid://6724771531",
					}, DropdownButton)

					local DropdownText = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Position       = UDim2.new(0, 9, 0, 6),
						Size           = UDim2.new(0, 200, 0, 9),
						Font           = Enum.Font.Ubuntu,
						Text           = text,
						TextColor3     = Color3.fromRGB(150, 150, 150),
						TextSize       = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
					}, Dropdown)

					local options_num = data.options and #data.options or 0
					local scrollSize  = options_num >= 4 and 80 or (20 * options_num)

					local DropdownScroll = Library:create("ScrollingFrame", {
						Active           = true,
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 9, 0, 41),
						Size             = UDim2.new(0, 260, 0, scrollSize),
						CanvasSize       = UDim2.new(0, 0, 0, 0),
						ScrollBarThickness = 2,
						TopImage         = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						BottomImage      = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						Visible          = false,
						ZIndex           = 2,
					}, Dropdown)

					if options_num >= 4 then
						for _ = 1, options_num do
							DropdownScroll.CanvasSize = DropdownScroll.CanvasSize + UDim2.new(0, 0, 0, 20)
						end
					end

					Library:create("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder           = Enum.SortOrder.LayoutOrder,
					}, DropdownScroll)

					local in_drop  = false
					local in_drop2 = false

					DropdownButton.MouseButton1Down:Connect(function()
						DropdownScroll.Visible = not DropdownScroll.Visible
						local open2 = DropdownScroll.Visible
						local col3 = open2 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 150)
						Library:Tween(DropdownText,       TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = col3 })
						Library:Tween(DropdownButtonText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = col3 })
					end)
					Dropdown.MouseEnter:Connect(function()       in_drop  = true  end)
					Dropdown.MouseLeave:Connect(function()       in_drop  = false end)
					DropdownScroll.MouseEnter:Connect(function() in_drop2 = true  end)
					DropdownScroll.MouseLeave:Connect(function() in_drop2 = false end)
					UserInputService.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.MouseButton2 then
							if DropdownScroll.Visible and not in_drop and not in_drop2 then
								DropdownScroll.Visible = false
								DropdownScroll.CanvasPosition = Vector2.new(0, 0)
								Library:Tween(DropdownText,       TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								Library:Tween(DropdownButtonText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
							end
						end
					end)

					local function update_combo_text()
						local opts = {}
						if data.options then
							for _, v2 in next, data.options do
								if table.find(value.Combo, v2) then
									table.insert(opts, v2)
								end
							end
						end
						if #opts == 0 then DropdownButtonText.Text = "..."
						elseif #opts == 1 then DropdownButtonText.Text = opts[1]
						else
							local t2 = opts[1]
							for i = 2, #opts do
								if i > 3 then if i < 5 then t2 = t2 .. ",  ..." end
								else t2 = t2 .. ",  " .. opts[i] end
							end
							DropdownButtonText.Text = t2
						end
					end

					function element:set_value(new_value, cb)
						value = new_value and new_value or value
						Library.Flags[flag] = value
						update_combo_text()
						if data.options then
							for _, DropButton in next, DropdownScroll:GetChildren() do
								if not DropButton:IsA("TextButton") then continue end
								local bt = DropButton:FindFirstChild("ButtonText")
								if bt then
									if table.find(value.Combo, DropButton.Name) then
										DropButton.Decoration.Visible = true
										bt.TextColor3 = Color3.fromRGB(255, 255, 255)
									else
										DropButton.Decoration.Visible = false
										bt.TextColor3 = Color3.fromRGB(150, 150, 150)
									end
								end
							end
						end
						if cb == nil or not cb then do_callback() end
					end

					Library.SetFlags[flag] = function(v) element:set_value(v) end

					if data.options then
						for _, v in next, data.options do
							local Btn = Library:create("TextButton", {
								Name             = v,
								BackgroundColor3 = Color3.fromRGB(25, 25, 25),
								BorderColor3     = Color3.fromRGB(0, 0, 0),
								BorderSizePixel  = 0,
								Size             = UDim2.new(1, 0, 0, 20),
								AutoButtonColor  = false,
								Font             = Enum.Font.SourceSans,
								Text             = "",
								ZIndex           = 2,
							}, DropdownScroll)

							local BtnText = Library:create("TextLabel", {
								Name             = "ButtonText",
								BackgroundTransparency = 1,
								Position       = UDim2.new(0, 8, 0, 0),
								Size           = UDim2.new(0, 245, 1, 0),
								Font           = Enum.Font.Ubuntu,
								Text           = v,
								TextColor3     = Color3.fromRGB(150, 150, 150),
								TextSize       = 14,
								TextXAlignment = Enum.TextXAlignment.Left,
								ZIndex         = 2,
							}, Btn)

							local Deco = Library:create("Frame", {
								Name             = "Decoration",
								BackgroundColor3 = Color3.fromRGB(84, 101, 255),
								BorderSizePixel  = 0,
								Size             = UDim2.new(0, 1, 1, 0),
								Visible          = false,
								ZIndex           = 2,
							}, Btn)

							local mouse_in_btn = false
							Btn.MouseEnter:Connect(function()
								mouse_in_btn = true
								if not table.find(value.Combo, v) then
									Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(200, 200, 200) })
								end
							end)
							Btn.MouseLeave:Connect(function()
								mouse_in_btn = false
								if not table.find(value.Combo, v) then
									Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								end
							end)
							Btn.MouseButton1Down:Connect(function()
								if table.find(value.Combo, v) then
									table.remove(value.Combo, table.find(value.Combo, v))
									Deco.Visible = false
									Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								else
									table.insert(value.Combo, v)
									Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) })
									Deco.Visible = true
								end
								update_combo_text()
								Library.Flags[flag] = value
								do_callback()
							end)
						end
					end

					element:set_value(value, true)

				-- ─────────────────── Button ────────────────────
				elseif etype == "Button" then
					local Border = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(5, 5, 5),
						BorderColor3     = Color3.fromRGB(30, 30, 30),
						Size             = UDim2.new(1, 0, 0, 30),
					}, col)

					local Container = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, Border)

					local ButtonFrame = Library:create("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 30),
					}, Container)

					local Button = Library:create("TextButton", {
						AnchorPoint      = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0.5, 0, 0.5, 0),
						Size             = UDim2.new(0, 215, 0, 20),
						AutoButtonColor  = false,
						Font             = Enum.Font.Ubuntu,
						Text             = text,
						TextColor3       = Color3.fromRGB(150, 150, 150),
						TextSize         = 14,
					}, ButtonFrame)

					Button.MouseEnter:Connect(function()
						Library:Tween(Button, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) })
					end)
					Button.MouseLeave:Connect(function()
						Library:Tween(Button, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
					end)
					Button.MouseButton1Down:Connect(function()
						Button.BorderColor3 = Color3.fromRGB(84, 101, 255)
						Library:Tween(Button, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BorderColor3 = Color3.fromRGB(0, 0, 0) })
						do_callback()
					end)

				-- ─────────────────── TextBox ───────────────────
				elseif etype == "TextBox" then
					local Border = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(5, 5, 5),
						BorderColor3     = Color3.fromRGB(30, 30, 30),
						Size             = UDim2.new(1, 0, 0, 30),
					}, col)

					local Container = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, Border)

					value = { Text = default and default or "" }

					local ButtonFrame = Library:create("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 30),
					}, Container)

					function element:set_visible(bool)
						if bool then
							if ButtonFrame.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, 30)
							ButtonFrame.Visible = true
						else
							if not ButtonFrame.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, -30)
							ButtonFrame.Visible = false
						end
					end

					local TextBox = Library:create("TextBox", {
						AnchorPoint      = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0.5, 0, 0.5, 0),
						Size             = UDim2.new(0, 215, 0, 20),
						Font             = Enum.Font.Ubuntu,
						Text             = value.Text,
						TextColor3       = Color3.fromRGB(150, 150, 150),
						TextSize         = 14,
						PlaceholderText  = text,
						ClearTextOnFocus = false,
					}, ButtonFrame)

					TextBox.MouseEnter:Connect(function()
						Library:Tween(TextBox, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) })
					end)
					TextBox.MouseLeave:Connect(function()
						Library:Tween(TextBox, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
					end)
					TextBox:GetPropertyChangedSignal("Text"):Connect(function()
						if string.len(TextBox.Text) > 50 then
							TextBox.Text = string.sub(TextBox.Text, 1, 50)
						end
						if TextBox.Text ~= value.Text then
							value.Text = TextBox.Text
							Library.Flags[flag] = value
							do_callback()
						end
					end)
					UserInputService.TextBoxFocused:connect(function()
						if UserInputService:GetFocusedTextBox() == TextBox then
							Library:Tween(TextBox, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BorderColor3 = Color3.fromRGB(84, 101, 255) })
						end
					end)
					UserInputService.TextBoxFocusReleased:connect(function()
						Library:Tween(TextBox, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BorderColor3 = Color3.fromRGB(0, 0, 0) })
					end)

					function element:set_value(new_value, cb)
						value = new_value or value
						Library.Flags[flag] = value
						TextBox.Text = value.Text
						if cb == nil or not cb then do_callback() end
					end

					Library.SetFlags[flag] = function(v)
						if type(v) == "string" then element:set_value({ Text = v })
						else element:set_value(v) end
					end

					element:set_value(value, true)

				-- ─────────────────── Slider ────────────────────
				elseif etype == "Slider" then
					local Border = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(5, 5, 5),
						BorderColor3     = Color3.fromRGB(30, 30, 30),
						Size             = UDim2.new(1, 0, 0, 35),
					}, col)

					local Container = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, Border)

					value = { Slider = default and default.default or 0 }

					local min_v = default and default.min or 0
					local max_v = default and default.max or 100

					local Slider = Library:create("Frame", {
						BackgroundColor3       = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 1,
						Size                   = UDim2.new(1, 0, 0, 35),
					}, Container)

					function element:set_visible(bool)
						if bool then
							if Slider.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, 35)
							Slider.Visible = true
						else
							if not Slider.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, -35)
							Slider.Visible = false
						end
					end

					local SliderText = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Position       = UDim2.new(0, 9, 0, 6),
						Size           = UDim2.new(0, 200, 0, 9),
						Font           = Enum.Font.Ubuntu,
						Text           = text,
						TextColor3     = Color3.fromRGB(150, 150, 150),
						TextSize       = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
					}, Slider)

					local SliderButton = Library:create("TextButton", {
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 9, 0, 20),
						Size             = UDim2.new(0, 260, 0, 10),
						AutoButtonColor  = false,
						Font             = Enum.Font.SourceSans,
						Text             = "",
					}, Slider)

					local SliderFrame = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BorderSizePixel  = 0,
						Size             = UDim2.new(0, 100, 1, 0),
					}, SliderButton)

					Library:create("UIGradient", {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(79,  95, 239)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(56,  67, 163)),
						}),
						Rotation = 90,
					}, SliderFrame)

					local SliderValue = Library:create("TextLabel", {
						BackgroundTransparency = 1,
						Position       = UDim2.new(0, 69, 0, 6),
						Size           = UDim2.new(0, 200, 0, 9),
						Font           = Enum.Font.Ubuntu,
						Text           = tostring(value.Slider),
						TextColor3     = Color3.fromRGB(150, 150, 150),
						TextSize       = 14,
						TextXAlignment = Enum.TextXAlignment.Right,
					}, Slider)

					local is_sliding = false
					local mouse_in   = false

					Slider.MouseEnter:Connect(function()
						Library:Tween(SliderText,  TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) })
						Library:Tween(SliderValue, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) })
						mouse_in = true
					end)
					Slider.MouseLeave:Connect(function()
						if not is_sliding then
							Library:Tween(SliderText,  TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
							Library:Tween(SliderValue, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
						end
						mouse_in = false
					end)

					local move_connection, release_connection

					SliderButton.MouseButton1Down:Connect(function()
						SliderFrame.Size = UDim2.new(0, math.clamp(Mouse.X - SliderFrame.AbsolutePosition.X, 0, 260), 1, 0)
						local val = math.floor((((max_v - min_v) / 260) * SliderFrame.AbsoluteSize.X) + min_v)
						if val ~= value.Slider then
							SliderValue.Text = val
							value.Slider = val
							Library.Flags[flag] = value
							do_callback()
						end
						is_sliding = true

						move_connection = Mouse.Move:Connect(function()
							SliderFrame.Size = UDim2.new(0, math.clamp(Mouse.X - SliderFrame.AbsolutePosition.X, 0, 260), 1, 0)
							local val2 = math.floor((((max_v - min_v) / 260) * SliderFrame.AbsoluteSize.X) + min_v)
							if val2 ~= value.Slider then
								SliderValue.Text = val2
								value.Slider = val2
								Library.Flags[flag] = value
								do_callback()
							end
						end)

						release_connection = UserInputService.InputEnded:Connect(function(m)
							if m.UserInputType == Enum.UserInputType.MouseButton1 then
								SliderFrame.Size = UDim2.new(0, math.clamp(Mouse.X - SliderFrame.AbsolutePosition.X, 0, 260), 1, 0)
								local val3 = math.floor((((max_v - min_v) / 260) * SliderFrame.AbsoluteSize.X) + min_v)
								if val3 ~= value.Slider then
									SliderValue.Text = val3
									value.Slider = val3
									Library.Flags[flag] = value
									do_callback()
								end
								is_sliding = false
								if not mouse_in then
									Library:Tween(SliderText,  TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
									Library:Tween(SliderValue, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
								end
								move_connection:Disconnect()
								release_connection:Disconnect()
							end
						end)
					end)

					function element:set_value(new_value, cb)
						value = new_value and new_value or value
						Library.Flags[flag] = value
						local new_size = (value.Slider - min_v) / (max_v - min_v)
						SliderFrame.Size = UDim2.new(new_size, 0, 1, 0)
						SliderValue.Text = tostring(value.Slider)
						if cb == nil or not cb then do_callback() end
					end

					Library.SetFlags[flag] = function(v)
						if type(v) == "number" then element:set_value({ Slider = v })
						else element:set_value(v) end
					end

					element:set_value(value, true)

				-- ─────────────────── Scroll ────────────────────
				elseif etype == "Scroll" then
					local scrollsize = data.scrollsize or 5
					local Border = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(5, 5, 5),
						BorderColor3     = Color3.fromRGB(30, 30, 30),
						Size             = UDim2.new(1, 0, 0, scrollsize * 20 + 10),
					}, col)

					local Container = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, Border)

					value = { Scroll = data.options and data.options[1] or "" }

					local Scroll = Library:create("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, scrollsize * 20 + 10),
					}, Container)

					function element:set_visible(bool)
						if bool then
							if Scroll.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, scrollsize * 20 + 10)
							Scroll.Visible = true
						else
							if not Scroll.Visible then return end
							Border.Size = Border.Size + UDim2.new(0, 0, 0, -(scrollsize * 20 + 10))
							Scroll.Visible = false
						end
					end

					local ScrollFrame = Library:create("ScrollingFrame", {
						Active           = true,
						BackgroundColor3 = Color3.fromRGB(25, 25, 25),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0.5, 0, 0, 5),
						Size             = UDim2.new(0, 215, 0, scrollsize * 20),
						BottomImage      = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						CanvasSize       = UDim2.new(0, 0, 0, (data.options and #data.options or 0) * 20),
						ScrollBarThickness = 2,
						TopImage         = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						AnchorPoint      = Vector2.new(0.5, 0),
						ScrollBarImageColor3 = Color3.fromRGB(84, 101, 255),
					}, Scroll)

					ScrollFrame.MouseEnter:Connect(function()
						Library:Tween(ScrollFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BorderColor3 = Color3.fromRGB(50, 50, 50) })
					end)
					ScrollFrame.MouseLeave:Connect(function()
						Library:Tween(ScrollFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BorderColor3 = Color3.fromRGB(0, 0, 0) })
					end)

					Library:create("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder           = Enum.SortOrder.LayoutOrder,
					}, ScrollFrame)

					local scroll_is_first = true

					local function make_scroll_btn(v)
						local Btn = Library:create("TextButton", {
							Name             = v,
							BackgroundColor3 = Color3.fromRGB(25, 25, 25),
							BorderColor3     = Color3.fromRGB(0, 0, 0),
							BorderSizePixel  = 0,
							Size             = UDim2.new(1, 0, 0, 20),
							AutoButtonColor  = false,
							Font             = Enum.Font.SourceSans,
							Text             = "",
						}, ScrollFrame)

						local BtnText = Library:create("TextLabel", {
							Name                   = "ButtonText",
							BackgroundColor3       = Color3.fromRGB(255, 255, 255),
							BackgroundTransparency = 1,
							Position               = UDim2.new(0, 7, 0, 0),
							Size                   = UDim2.new(0, 210, 1, 0),
							Font                   = Enum.Font.Ubuntu,
							Text                   = v,
							TextColor3             = Color3.fromRGB(150, 150, 150),
							TextSize               = 14,
							TextXAlignment         = Enum.TextXAlignment.Left,
						}, Btn)

						local Deco = Library:create("Frame", {
							Name             = "Decoration",
							BackgroundColor3 = Color3.fromRGB(84, 101, 255),
							BorderSizePixel  = 0,
							Size             = UDim2.new(0, 1, 1, 0),
							Visible          = false,
						}, Btn)

						Btn.MouseEnter:Connect(function()
							if value.Scroll ~= v then
								Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(200, 200, 200) })
							end
						end)
						Btn.MouseLeave:Connect(function()
							if value.Scroll ~= v then
								Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) })
							end
						end)
						Btn.MouseButton1Down:Connect(function()
							for _, b2 in next, ScrollFrame:GetChildren() do
								if not b2:IsA("TextButton") then continue end
								local d = b2:FindFirstChild("Decoration")
								local t2 = b2:FindFirstChild("ButtonText")
								if d then d.Visible = false end
								if t2 then Library:Tween(t2, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) }) end
							end
							Library.Flags[flag] = value
							Deco.Visible = true
							Library:Tween(BtnText, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) })
							value.Scroll = v
							do_callback()
						end)

						if scroll_is_first then
							scroll_is_first = false
							Deco.Visible = true
							BtnText.TextColor3 = Color3.fromRGB(255, 255, 255)
						end
					end

					if data.options then
						for _, v in next, data.options do make_scroll_btn(v) end
					end

					function element:add_value(v)
						if ScrollFrame:FindFirstChild(v) then return end
						ScrollFrame.CanvasSize = ScrollFrame.CanvasSize + UDim2.new(0, 0, 0, 20)
						make_scroll_btn(v)
					end

					function element:set_value(new_value, cb)
						value = new_value or value
						Library.Flags[flag] = value
						for _, b2 in next, ScrollFrame:GetChildren() do
							if not b2:IsA("TextButton") then continue end
							local d  = b2:FindFirstChild("Decoration")
							local t2 = b2:FindFirstChild("ButtonText")
							if d  then d.Visible  = false end
							if t2 then Library:Tween(t2, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(150, 150, 150) }) end
						end
						local target = ScrollFrame:FindFirstChild(value.Scroll)
						if target then
							local d = target:FindFirstChild("Decoration")
							local t2 = target:FindFirstChild("ButtonText")
							if d  then d.Visible  = true end
							if t2 then Library:Tween(t2, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(255, 255, 255) }) end
						end
						if cb == nil or not cb then do_callback() end
					end

					Library.SetFlags[flag] = function(v) element:set_value(v) end

					element:set_value(value, true)
				end

				-- OnLoad: re-apply saved value
				OnLoad:Connect(function()
					if etype ~= "Button" and etype ~= "Scroll" then
						if element.set_value and Library.Flags[flag] then
							element:set_value(Library.Flags[flag])
						end
					end
				end)

				return element
			end -- make_element

			-- ──────────────────────────────────────────────────
			-- Utopia-named methods on Section
			-- Each maps to make_element with the right etype,
			-- translates Utopia Data table → newgui args,
			-- and wires Keybind / Colorpicker chains.
			-- ──────────────────────────────────────────────────

			function Section:Toggle(Data4)
				Data4 = Data4 or {}
				local flag  = Data4.Flag or Data4.flag or Library:NextFlag()
				local col2  = column(Data4.Side or Data4.side or 1)

				local element = make_element(col2, "Toggle",
					Data4.Name or Data4.name or "Toggle",
					{ default = Data4.Default ~= nil and { Toggle = Data4.Default }
					         or (Data4.default ~= nil and { Toggle = Data4.default } or { Toggle = false }) },
					function(v)
						Library.Flags[flag] = v.Toggle
						if Data4.Callback then Library:SafeCall(Data4.Callback, v.Toggle)
						elseif Data4.callback then Library:SafeCall(Data4.callback, v.Toggle) end
					end,
					flag -- use the Utopia flag directly as c_flag
				)

				-- Override the flag key so Library.Flags[Data4.Flag] is the boolean
				-- (make_element stores {Toggle=bool}, we also store the raw bool)
				local orig_set = element.set_value
				function element:set_value(new_value, cb)
					orig_set(self, new_value, cb)
					if type(new_value) == "table" then
						Library.Flags[flag] = new_value.Toggle
					end
				end

				Library.SetFlags[flag] = function(v)
					if type(v) == "boolean" then element:set_value({ Toggle = v })
					elseif type(v) == "table" and v.Toggle ~= nil then element:set_value(v)
					end
				end

				-- Utopia chain methods
				local Toggle = element

				function Toggle:Set(v)
					element:set_value(type(v) == "boolean" and { Toggle = v } or v)
				end
				function Toggle:Get()
					return Library.Flags[flag]
				end
				function Toggle:SetVisibility(v)
					element:set_visible(v)
				end

				function Toggle:Keybind(KbData)
					KbData = KbData or {}
					local kbFlag = KbData.Flag or KbData.flag or Library:NextFlag()
					local keybind = element:add_keybind(
						KbData.Default and { Key = tostring(KbData.Default), Type = KbData.Mode or "Toggle", Active = false } or nil,
						function(v)
							Library.Flags[kbFlag] = v
							if KbData.Callback then Library:SafeCall(KbData.Callback, v.Active) end
						end
					)
					if keybind then
						Library.SetFlags[kbFlag] = function(v) keybind:set_value(v) end
					end
					return Toggle -- chain returns Toggle so :Keybind() is chainable
				end

				function Toggle:Colorpicker(CpData)
					CpData = CpData or {}
					local cpFlag = CpData.Flag or CpData.flag or Library:NextFlag()
					local color = element:add_color(
						CpData.Default and { Color = CpData.Default } or { Color = Color3.fromRGB(255, 255, 255) },
						CpData.Alpha or false,
						function(v)
							Library.Flags[cpFlag] = v.Color
							if CpData.Callback then Library:SafeCall(CpData.Callback, v.Color, v.Transparency) end
						end
					)
					if color then
						Library.SetFlags[cpFlag] = function(v) color:set_value(type(v) == "table" and v or { Color = v }) end
					end

					local Cp = {}
					function Cp:Set(c, a) if color then color:set_value({ Color = c, Transparency = a or 0 }) end end
					function Cp:Get()     return Library.Flags[cpFlag] end
					function Cp:SetVisibility(b) end -- swatch visibility not separately controllable in newgui
					return Cp
				end

				return Toggle
			end

			function Section:Button(Data4)
				Data4 = Data4 or {}
				local flag = Data4.Flag or Data4.flag or Library:NextFlag()
				local col2 = column(Data4.Side or Data4.side or 1)

				local element = make_element(col2, "Button",
					Data4.Name or Data4.name or "Button",
					{},
					function(_v)
						if Data4.Callback then Library:SafeCall(Data4.Callback)
						elseif Data4.callback then Library:SafeCall(Data4.callback) end
					end,
					flag
				)

				local Btn = {}
				function Btn:SetVisibility(v) element:set_visible and element:set_visible(v) end
				return Btn
			end

			function Section:Slider(Data4)
				Data4 = Data4 or {}
				local flag = Data4.Flag or Data4.flag or Library:NextFlag()
				local col2 = column(Data4.Side or Data4.side or 1)

				local element = make_element(col2, "Slider",
					Data4.Name or Data4.name or "Slider",
					{
						default = Data4.Default or Data4.default or 0,
						min     = Data4.Min     or Data4.min     or 0,
						max     = Data4.Max     or Data4.max     or 100,
					},
					function(v)
						Library.Flags[flag] = v.Slider
						if Data4.Callback then Library:SafeCall(Data4.Callback, v.Slider)
						elseif Data4.callback then Library:SafeCall(Data4.callback, v.Slider) end
					end,
					flag
				)

				Library.SetFlags[flag] = function(v)
					if type(v) == "number" then element:set_value({ Slider = v })
					elseif type(v) == "table" then element:set_value(v) end
				end

				local Sl = {}
				function Sl:Set(v)           element:set_value({ Slider = v }) end
				function Sl:Get()            return Library.Flags[flag] end
				function Sl:SetVisibility(v) element:set_visible(v) end
				return Sl
			end

			function Section:Dropdown(Data4)
				Data4 = Data4 or {}
				local flag    = Data4.Flag or Data4.flag or Library:NextFlag()
				local col2    = column(Data4.Side or Data4.side or 1)
				local isMulti = Data4.Multi or Data4.multi or false

				local etype   = isMulti and "Combo" or "Dropdown"

				local element = make_element(col2, etype,
					Data4.Name or Data4.name or "Dropdown",
					{
						options = Data4.Items or Data4.items or {},
						default = isMulti
							and (Data4.Default and { Combo = type(Data4.Default) == "table" and Data4.Default or { Data4.Default } } or { Combo = {} })
							or  (Data4.Default and { Dropdown = Data4.Default } or nil),
					},
					function(v)
						local val = isMulti and v.Combo or v.Dropdown
						Library.Flags[flag] = val
						if Data4.Callback then Library:SafeCall(Data4.Callback, val)
						elseif Data4.callback then Library:SafeCall(Data4.callback, val) end
					end,
					flag
				)

				Library.SetFlags[flag] = function(v)
					if isMulti then
						element:set_value(type(v) == "table" and { Combo = v } or v)
					else
						element:set_value(type(v) == "string" and { Dropdown = v } or v)
					end
				end

				local Dd = {}
				function Dd:Set(v)
					Library.SetFlags[flag](v)
				end
				function Dd:Get()            return Library.Flags[flag] end
				function Dd:SetVisibility(v) element:set_visible(v) end
				-- Refresh / Add / Remove not trivially supported in newgui's baked list
				-- but we expose stubs for API compat
				function Dd:Refresh(_list) end
				function Dd:Add(_opt)      end
				function Dd:Remove(_opt)   end
				return Dd
			end

			function Section:Label(Text, Alignment)
				local col2 = Left -- labels always go left unless caller specifies otherwise
				local flag  = Library:NextFlag()

				-- Labels in newgui don't have a direct element type.
				-- We create a simple TextLabel in the column.
				local Border = Library:create("Frame", {
					BackgroundColor3 = Color3.fromRGB(5, 5, 5),
					BorderColor3     = Color3.fromRGB(30, 30, 30),
					Size             = UDim2.new(1, 0, 0, 18),
				}, col2)

				local Container = Library:create("Frame", {
					BackgroundColor3 = Color3.fromRGB(10, 10, 10),
					BorderSizePixel  = 0,
					Position         = UDim2.new(0, 1, 0, 1),
					Size             = UDim2.new(1, -2, 1, -2),
				}, Border)

				local xAlign = Alignment == "Right" and Enum.TextXAlignment.Right
				           or (Alignment == "Center" and Enum.TextXAlignment.Center)
				           or Enum.TextXAlignment.Left

				Library:create("TextLabel", {
					BackgroundTransparency = 1,
					Size           = UDim2.new(1, 0, 1, 0),
					Font           = Enum.Font.Ubuntu,
					Text           = Text or "",
					TextColor3     = Color3.fromRGB(150, 150, 150),
					TextSize       = 14,
					TextXAlignment = xAlign,
					RichText       = true,
				}, Container)

				local Lbl = {}
				function Lbl:SetVisibility(v) Border.Visible = v end

				-- Labels can host Colorpicker (Utopia compat)
				function Lbl:Colorpicker(CpData)
					CpData = CpData or {}
					local cpFlag = CpData.Flag or CpData.flag or Library:NextFlag()

					-- We need a dummy Toggle element just for add_color
					-- So we make an invisible toggle row and immediately add color to it
					local dummy_border = Library:create("Frame", {
						BackgroundTransparency = 1,
						Size   = UDim2.new(1, 0, 0, 0),
					}, col2)

					local dummy_container = Library:create("Frame", {
						BackgroundTransparency = 1,
						BorderSizePixel  = 0,
						Position         = UDim2.new(0, 1, 0, 1),
						Size             = UDim2.new(1, -2, 1, -2),
					}, dummy_border)

					local dummy_btn = Library:create("TextButton", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 18),
						Text = "",
					}, Container) -- inside the label's container

					-- Reuse make_element logic for colorpicker by making a minimal toggle wrapper
					local dummyElement = { add_color = nil }
					local dummy_ToggleButton = dummy_btn

					-- Duplicate the add_color closure inline using the same pattern
					local color = {}
					local extra_value = { Color = CpData.Default or Color3.fromRGB(255, 255, 255) }
					local color_callback = function(v)
						Library.Flags[cpFlag] = v.Color
						if CpData.Callback then Library:SafeCall(CpData.Callback, v.Color) end
					end

					Library.Flags[cpFlag] = extra_value

					local ColorButton = Library:create("TextButton", {
						AnchorPoint      = Vector2.new(1, 0.5),
						BackgroundColor3 = extra_value.Color,
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(1, -4, 0.5, 0),
						Size             = UDim2.new(0, 35, 0, 11),
						AutoButtonColor  = false,
						Text             = "",
					}, Container)

					local ColorFrame = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(10, 10, 10),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(1, 5, 0, 0),
						Size             = UDim2.new(0, 200, 0, 170),
						Visible          = false,
						ZIndex           = 2,
					}, ColorButton)

					local ColorPicker = Library:create("ImageButton", {
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 40, 0, 10),
						Size             = UDim2.new(0, 150, 0, 150),
						AutoButtonColor  = false,
						Image            = "rbxassetid://4155801252",
						ImageColor3      = Color3.fromRGB(255, 0, 4),
						ZIndex           = 2,
					}, ColorFrame)

					local ColorPick = Library:create("Frame", {
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Size             = UDim2.new(0, 1, 0, 1),
						ZIndex           = 2,
					}, ColorPicker)

					local HuePicker = Library:create("TextButton", {
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Position         = UDim2.new(0, 10, 0, 10),
						Size             = UDim2.new(0, 20, 0, 150),
						ZIndex           = 2,
						AutoButtonColor  = false,
						Text             = "",
					}, ColorFrame)

					Library:create("UIGradient", {
						Rotation = 90,
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0,   0)),
							ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 0, 255)),
							ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0,   0, 255)),
							ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
							ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 255,   0)),
							ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 255,   0)),
							ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0,   0)),
						}),
					}, HuePicker)

					local HuePick = Library:create("ImageButton", {
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BorderColor3     = Color3.fromRGB(0, 0, 0),
						Size             = UDim2.new(1, 0, 0, 1),
						ZIndex           = 2,
					}, HuePicker)

					color.h = 0; color.s = 1; color.v = 1

					local in_c = false; local in_c2 = false

					ColorButton.MouseButton1Down:Connect(function() ColorFrame.Visible = not ColorFrame.Visible end)
					ColorFrame.MouseEnter:Connect(function() in_c = true end)
					ColorFrame.MouseLeave:Connect(function() in_c = false end)
					ColorButton.MouseEnter:Connect(function() in_c2 = true end)
					ColorButton.MouseLeave:Connect(function() in_c2 = false end)
					UserInputService.InputBegan:Connect(function(inp)
						if (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.MouseButton2)
						and ColorFrame.Visible and not in_c and not in_c2 then
							ColorFrame.Visible = false
						end
					end)

					local function upd_color()
						local cx = math.clamp(Mouse.X - ColorPicker.AbsolutePosition.X, 0, ColorPicker.AbsoluteSize.X) / ColorPicker.AbsoluteSize.X
						local cy = math.clamp(Mouse.Y - ColorPicker.AbsolutePosition.Y, 0, ColorPicker.AbsoluteSize.Y) / ColorPicker.AbsoluteSize.Y
						ColorPick.Position = UDim2.new(cx, 0, cy, 0)
						color.s = 1 - cx; color.v = 1 - cy
						ColorButton.BackgroundColor3 = Color3.fromHSV(color.h, color.s, color.v)
						extra_value.Color = Color3.fromHSV(color.h, color.s, color.v)
						color_callback(extra_value)
					end
					ColorPicker.MouseButton1Down:Connect(function()
						upd_color()
						local mc = Mouse.Move:Connect(upd_color)
						local rc; rc = UserInputService.InputEnded:Connect(function(m)
							if m.UserInputType == Enum.UserInputType.MouseButton1 then upd_color(); mc:Disconnect(); rc:Disconnect() end
						end)
					end)

					local function upd_hue()
						local y = math.clamp(Mouse.Y - HuePicker.AbsolutePosition.Y, 0, 148)
						HuePick.Position = UDim2.new(0, 0, 0, y)
						color.h = 1 - y / 148
						ColorPicker.ImageColor3 = Color3.fromHSV(color.h, 1, 1)
						ColorButton.BackgroundColor3 = Color3.fromHSV(color.h, color.s, color.v)
						extra_value.Color = Color3.fromHSV(color.h, color.s, color.v)
						color_callback(extra_value)
					end
					HuePicker.MouseButton1Down:Connect(function()
						upd_hue()
						local mc = Mouse.Move:Connect(upd_hue)
						local rc; rc = UserInputService.InputEnded:Connect(function(m)
							if m.UserInputType == Enum.UserInputType.MouseButton1 then upd_hue(); mc:Disconnect(); rc:Disconnect() end
						end)
					end)

					local Cp = {}
					function Cp:Set(c)
						extra_value.Color = c
						Library.Flags[cpFlag] = c
						color.h, color.s, color.v = c:ToHSV()
						ColorPick.Position = UDim2.new(1 - color.s, 0, 1 - color.v, 0)
						ColorPicker.ImageColor3 = Color3.fromHSV(color.h, 1, 1)
						ColorButton.BackgroundColor3 = c
						HuePick.Position = UDim2.new(0, 0, 1 - color.h, -1)
						if CpData.Callback and not Library.IsLoading then Library:SafeCall(CpData.Callback, c) end
					end
					function Cp:Get() return Library.Flags[cpFlag] end
					function Cp:SetVisibility(v) ColorButton.Visible = v end

					Library.SetFlags[cpFlag] = function(v)
						if typeof(v) == "Color3" then Cp:Set(v)
						elseif type(v) == "string" then Cp:Set(Color3.fromHex(v))
						elseif type(v) == "table" and v.Color then Cp:Set(v.Color) end
					end

					if CpData.Default then Cp:Set(CpData.Default) end

					return Cp
				end

				-- Labels can also host Keybind (Utopia compat) — same as standalone
				function Lbl:Keybind(KbData)
					KbData = KbData or {}
					local kbFlag = KbData.Flag or KbData.flag or Library:NextFlag()

					-- Create a minimal keybind button inside the label container
					local Keybind = Library:create("TextButton", {
						AnchorPoint        = Vector2.new(1, 0.5),
						BackgroundTransparency = 1,
						Position           = UDim2.new(1, -4, 0.5, 0),
						Size               = UDim2.new(0, 56, 0, 18),
						Font               = Enum.Font.Ubuntu,
						Text               = "[ NONE ]",
						TextColor3         = Color3.fromRGB(150, 150, 150),
						TextSize           = 14,
						TextXAlignment     = Enum.TextXAlignment.Right,
					}, Container)

					local kb_value = { Key = nil, Type = KbData.Mode or "Toggle", Active = false }
					Library.Flags[kbFlag] = kb_value

					local function setKbText()
						local k = kb_value.Key or "NONE"
						Keybind.Text = "[ " .. k:upper() .. " ]"
					end

					Keybind.MouseButton1Click:Connect(function()
						Keybind.Text = "[ ... ]"
						local conn; conn = UserInputService.InputBegan:Connect(function(inp)
							local name = inp.KeyCode.Name ~= "Unknown" and inp.KeyCode.Name or inp.UserInputType.Name
							if name == "Backspace" then kb_value.Key = nil else kb_value.Key = name end
							setKbText()
							Library.Flags[kbFlag] = kb_value
							if KbData.Callback and not Library.IsLoading then Library:SafeCall(KbData.Callback, kb_value) end
							conn:Disconnect()
						end)
					end)

					UserInputService.InputBegan:Connect(function(inp)
						if UserInputService:GetFocusedTextBox() then return end
						local k = inp.KeyCode.Name ~= "Unknown" and inp.KeyCode.Name or inp.UserInputType.Name
						if k == kb_value.Key then
							if kb_value.Type == "Toggle" then kb_value.Active = not kb_value.Active
							elseif kb_value.Type == "Hold" then kb_value.Active = true
							elseif kb_value.Type == "Always" then kb_value.Active = true end
							Library.Flags[kbFlag] = kb_value
							if KbData.Callback and not Library.IsLoading then Library:SafeCall(KbData.Callback, kb_value) end
						end
					end)
					UserInputService.InputEnded:Connect(function(inp)
						local k = inp.KeyCode.Name ~= "Unknown" and inp.KeyCode.Name or inp.UserInputType.Name
						if k == kb_value.Key and kb_value.Type == "Hold" then
							kb_value.Active = false
							Library.Flags[kbFlag] = kb_value
							if KbData.Callback and not Library.IsLoading then Library:SafeCall(KbData.Callback, kb_value) end
						end
					end)

					local Kb = {}
					function Kb:Set(v)
						if type(v) == "table" then kb_value = v; Library.Flags[kbFlag] = v; setKbText() end
					end
					function Kb:Get() return kb_value end
					function Kb:SetVisibility(v) Keybind.Visible = v end

					Library.SetFlags[kbFlag] = function(v) Kb:Set(v) end

					if KbData.Default then
						kb_value.Key = tostring(KbData.Default):gsub("Enum%.KeyCode%.", "")
						setKbText()
					end

					return Kb
				end

				return Lbl
			end

			function Section:Textbox(Data4)
				Data4 = Data4 or {}
				local flag = Data4.Flag or Data4.flag or Library:NextFlag()
				local col2 = column(Data4.Side or Data4.side or 1)

				local element = make_element(col2, "TextBox",
					Data4.Placeholder or Data4.placeholder or Data4.Name or Data4.name or "TextBox",
					{ default = Data4.Default or Data4.default or "" },
					function(v)
						Library.Flags[flag] = v.Text
						if Data4.Callback then Library:SafeCall(Data4.Callback, v.Text)
						elseif Data4.callback then Library:SafeCall(Data4.callback, v.Text) end
					end,
					flag
				)

				Library.SetFlags[flag] = function(v)
					if type(v) == "string" then element:set_value({ Text = v })
					elseif type(v) == "table" then element:set_value(v) end
				end

				local Tb = {}
				function Tb:Set(v)           element:set_value({ Text = tostring(v) }) end
				function Tb:Get()            return Library.Flags[flag] end
				function Tb:SetVisibility(v) element:set_visible(v) end
				return Tb
			end

			function Section:Listbox(Data4)
				Data4 = Data4 or {}
				local flag = Data4.Flag or Data4.flag or Library:NextFlag()
				local col2 = column(Data4.Side or Data4.side or 1)
				local scrollRows = Data4.Size or Data4.size or 5

				local element = make_element(col2, "Scroll",
					Data4.Name or Data4.name or "Listbox",
					{
						options    = Data4.Items or Data4.items or {},
						scrollsize = math.ceil(scrollRows / 20), -- rows visible
					},
					function(v)
						Library.Flags[flag] = v.Scroll
						if Data4.Callback then Library:SafeCall(Data4.Callback, v.Scroll)
						elseif Data4.callback then Library:SafeCall(Data4.callback, v.Scroll) end
					end,
					flag
				)

				Library.SetFlags[flag] = function(v)
					if type(v) == "string" then element:set_value({ Scroll = v })
					elseif type(v) == "table" then element:set_value(v) end
				end

				local Lb = {}
				function Lb:Set(v)    element:set_value({ Scroll = v }) end
				function Lb:Get()     return Library.Flags[flag] end
				function Lb:Add(v)    element:add_value(v) end
				function Lb:Remove(_) end
				function Lb:Refresh(list)
					-- rebuild: not directly supported; best-effort
				end
				function Lb:SetVisibility(v) element:set_visible(v) end
				return Lb
			end

			-- Expose `sector` compat surface so old-style code still works
			Section.new_sector = function(_, name, side)
				return Section -- delegate to self; newgui sector = Utopia Section
			end

			setmetatable(Section, Library.Sections)
			return Section
		end -- Page:Section

		setmetatable(Page, Library.Pages)
		return Page
	end -- Window:Page

	setmetatable(Window, Library)
	return Window
end -- Library:Window

-- ──────────────────────────────────────────────────────────────
-- Finalise
-- ──────────────────────────────────────────────────────────────
Library.IsLoading = false

getgenv().Library = Library
return Library
