--!nolint UnknownGlobal
--!nocheck

if getgenv().Library then
    getgenv().Library:Unload()
end

if (not getgenv().cloneref) then
    getgenv().cloneref = function(...) return ... end
end

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = cloneref(game:GetService("HttpService"))
local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local FromRGB = Color3.fromRGB
local FromHSV = Color3.fromHSV
local UDim2New = UDim2.new
local UDimNew = UDim.new
local Vector2New = Vector2.new
local InstanceNew = Instance.new
local MathClamp = math.clamp
local MathFloor = math.floor
local TableInsert = table.insert
local TableFind = table.find
local TableRemove = table.remove
local StringFormat = string.format
local StringFind = string.find
local StringGSub = string.gsub

-- ============================================================
-- Library core (Utopia-compatible)
-- ============================================================
local Library = {
    Flags      = {},
    SetFlags   = {},
    IsLoading  = true,

    MenuKeybind = tostring(Enum.KeyCode.Insert),

    Pages    = {},
    Sections = {},

    Connections = {},
    Threads     = {},

    CurrentFrames = {},

    UnnamedConnections = 0,
    UnnamedFlags       = 0,

    OnUnloadCallbacks = {},

    Holder      = nil,
    NotifHolder = nil,
}

Library.__index    = Library
Library.Pages.__index    = Library.Pages
Library.Sections.__index = Library.Sections

getgenv().Library = Library

-- ── helpers ──────────────────────────────────────────────────

function Library:NextFlag()
    self.UnnamedFlags = self.UnnamedFlags + 1
    return StringFormat("Flag_%d_%s", self.UnnamedFlags, HttpService:GenerateGUID(false))
end

function Library:SafeCall(fn, ...)
    if not fn or type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then warn(err) end
    return ok
end

function Library:Thread(fn)
    local t = coroutine.create(fn)
    coroutine.wrap(function() coroutine.resume(t) end)()
    TableInsert(self.Threads, t)
    return t
end

function Library:Connect(event, callback, name)
    name = name or StringFormat("Conn_%d_%s", self.UnnamedConnections + 1, HttpService:GenerateGUID(false))
    self.UnnamedConnections = self.UnnamedConnections + 1

    local wrapped = function(...)
        if self.Unloaded then return end
        return callback(...)
    end

    local entry = { Event = event, Callback = wrapped, Name = name, Connection = nil }
    self:Thread(function()
        entry.Connection = event:Connect(wrapped)
    end)
    TableInsert(self.Connections, entry)
    return entry
end

function Library:Disconnect(name)
    for _, c in self.Connections do
        if c.Name == name then
            if c.Connection then pcall(function() c.Connection:Disconnect() end) end
            break
        end
    end
end

function Library:OnUnload(cb)
    if type(cb) == "function" then TableInsert(self.OnUnloadCallbacks, cb) end
end

function Library:Unload()
    self.Unloaded = true
    for _, cb in next, self.OnUnloadCallbacks do pcall(cb) end
    for _, c  in self.Connections do if c.Connection then pcall(function() c.Connection:Disconnect() end) end end
    for _, t  in self.Threads     do pcall(coroutine.close, t) end
    if self.Holder then self.Holder:Destroy() end
    self.Flags = nil
    self.Connections = {}
    self.Threads = {}
    self.OnUnloadCallbacks = nil
    getgenv().Library = nil
end

function Library:IsMouseOverFrame(frame)
    local ap = frame.AbsolutePosition
    local as = frame.AbsoluteSize
    return Mouse.X >= ap.X and Mouse.X <= ap.X + as.X
        and Mouse.Y >= ap.Y and Mouse.Y <= ap.Y + as.Y
end

function Library:Tween(instance, info, props)
    TweenService:Create(instance, info, props):Play()
end

local TWEEN_FAST = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ── ScreenGui ────────────────────────────────────────────────

Library.Holder = InstanceNew("ScreenGui")
Library.Holder.Name            = "\0"
Library.Holder.ResetOnSpawn    = false
Library.Holder.ZIndexBehavior  = Enum.ZIndexBehavior.Global
Library.Holder.IgnoreGuiInset  = true
Library.Holder.Parent          = CoreGui

-- ============================================================
-- Dragging helper
-- ============================================================
local function MakeDraggable(gui)
    local dragging, dragStart, startPos

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

    UserInputService.InputChanged:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseMovement
        or  input.UserInputType == Enum.UserInputType.Touch) and dragging then
            local d = input.Position - dragStart
            gui.Position = UDim2New(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- ============================================================
-- create() shorthand (preserves newgui style)
-- ============================================================
local function create(class, props, parent)
    local obj = InstanceNew(class)
    for k, v in pairs(props) do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end

local function getTextSize(text, size, font, bounds)
    return TextService:GetTextSize(text, size, font, bounds)
end

-- ============================================================
-- Window constructor  (Library:Window)
-- ============================================================
function Library:Window(data)
    data = data or {}

    local Window = {
        Name    = data.Name or data.name or "Window",
        IsOpen  = true,
        Pages   = {},
        Sections= {},
        Items   = {},
    }

    -- ── Root frame ─────────────────────────────────────────
    local Root = create("ImageButton", {
        Name             = "Main",
        AnchorPoint      = Vector2New(0.5, 0.5),
        BackgroundColor3 = FromRGB(15, 15, 15),
        BorderColor3     = FromRGB(78, 93, 234),
        Position         = UDim2New(0.5, 0, 0.5, 0),
        Size             = data.Size or UDim2New(0, 700, 0, 500),
        Image            = "http://www.roblox.com/asset/?id=7300333488",
        AutoButtonColor  = false,
        Modal            = true,
    }, Library.Holder)

    MakeDraggable(Root)

    -- ── Title bar ──────────────────────────────────────────
    local Title = create("TextLabel", {
        Name               = "Title",
        AnchorPoint        = Vector2New(0.5, 0),
        BackgroundTransparency = 1,
        Position           = UDim2New(0.5, 0, 0, 0),
        Size               = UDim2New(1, -22, 0, 30),
        Font               = Enum.Font.Ubuntu,
        Text               = Window.Name,
        TextColor3         = FromRGB(255, 255, 255),
        TextSize           = 16,
        TextXAlignment     = Enum.TextXAlignment.Left,
        RichText           = true,
    }, Root)

    -- ── Tab buttons column ─────────────────────────────────
    local TabButtons = create("Frame", {
        Name               = "TabButtons",
        BackgroundTransparency = 1,
        Position           = UDim2New(0, 12, 0, 41),
        Size               = UDim2New(0, 76, 0, 447),
    }, Root)

    create("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center }, TabButtons)

    -- ── Tab content area ───────────────────────────────────
    local Tabs = create("Frame", {
        Name               = "Tabs",
        BackgroundTransparency = 1,
        Position           = UDim2New(0, 102, 0, 42),
        Size               = UDim2New(0, 586, 0, 446),
    }, Root)

    local isFirstTab  = true
    local selectedTab = nil

    -- ── Window:SetOpen ────────────────────────────────────
    function Window:SetOpen(bool)
        Window.IsOpen    = bool
        Root.Visible     = bool
    end

    -- ── Toggle on MenuKeybind ─────────────────────────────
    Library:Connect(UserInputService.InputBegan, function(input, gp)
        if gp then return end
        if tostring(input.KeyCode) == Library.MenuKeybind
        or tostring(input.UserInputType) == Library.MenuKeybind then
            Window:SetOpen(not Window.IsOpen)
        end
    end)

    Window.Items = { Root = Root, TabButtons = TabButtons, Tabs = Tabs }

    -- ── Window:Page ───────────────────────────────────────
    function Window:Page(data2)
        data2 = data2 or {}

        local Page = {
            Window      = Window,
            Name        = data2.Name or data2.name or "Page",
            ColumnsData = {},
            Items       = {},
        }

        -- Tab icon button
        local TabButton = create("TextButton", {
            BackgroundTransparency = 1,
            Size   = UDim2New(0, 76, 0, 76),
            Text   = "",
        }, TabButtons)

        local TabImage = create("ImageLabel", {
            AnchorPoint        = Vector2New(0.5, 0.5),
            BackgroundTransparency = 1,
            Position           = UDim2New(0.5, 0, 0.5, 0),
            Size               = UDim2New(0, 32, 0, 32),
            Image              = data2.Icon or "",
            ImageColor3        = FromRGB(100, 100, 100),
        }, TabButton)

        -- Fallback: if no icon, show text label in the tab button
        if (data2.Icon == nil or data2.Icon == "") and (data2.Name or data2.name) then
            TabImage.Visible = false
            create("TextLabel", {
                BackgroundTransparency = 1,
                Size           = UDim2New(1, 0, 1, 0),
                Font           = Enum.Font.Ubuntu,
                Text           = data2.Name or data2.name or "",
                TextColor3     = FromRGB(100, 100, 100),
                TextSize       = 13,
                TextWrapped    = true,
            }, TabButton)
        end

        -- Tab frame (content)
        local Tab = create("Frame", {
            BackgroundTransparency = 1,
            Size    = UDim2New(1, 0, 1, 0),
            Visible = false,
        }, Tabs)

        -- Section bar (sub-pages)
        local TabSections = create("Frame", {
            BackgroundTransparency = 1,
            Size             = UDim2New(1, 0, 0, 28),
            ClipsDescendants = true,
        }, Tab)

        create("UIListLayout", {
            FillDirection        = Enum.FillDirection.Horizontal,
            HorizontalAlignment  = Enum.HorizontalAlignment.Center,
        }, TabSections)

        -- Content frames area
        local TabFrames = create("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2New(0, 0, 0, 29),
            Size     = UDim2New(1, 0, 0, 418),
        }, Tab)

        -- First tab auto-visible
        if isFirstTab then
            isFirstTab   = false
            selectedTab  = TabButton
            TabImage.ImageColor3 = FromRGB(84, 101, 255)
            Tab.Visible  = true

            -- Apply text colour to first text-fallback label too
            for _, c in ipairs(TabButton:GetChildren()) do
                if c:IsA("TextLabel") then c.TextColor3 = FromRGB(84, 101, 255) end
            end
        end

        TabButton.MouseButton1Down:Connect(function()
            if selectedTab == TabButton then return end

            -- Deselect all tabs
            for _, tb in ipairs(TabButtons:GetChildren()) do
                if tb:IsA("TextButton") then
                    Library:Tween(tb:FindFirstChildWhichIsA("ImageLabel") or tb, TWEEN_FAST,
                        { ImageColor3 = FromRGB(100, 100, 100) })
                    for _, c in ipairs(tb:GetChildren()) do
                        if c:IsA("TextLabel") then
                            Library:Tween(c, TWEEN_FAST, { TextColor3 = FromRGB(100, 100, 100) })
                        end
                    end
                end
            end
            for _, t in ipairs(Tabs:GetChildren()) do t.Visible = false end

            Tab.Visible = true
            selectedTab = TabButton
            Library:Tween(TabImage, TWEEN_FAST, { ImageColor3 = FromRGB(84, 101, 255) })
            for _, c in ipairs(TabButton:GetChildren()) do
                if c:IsA("TextLabel") then
                    Library:Tween(c, TWEEN_FAST, { TextColor3 = FromRGB(84, 101, 255) })
                end
            end
        end)

        TabButton.MouseEnter:Connect(function()
            if selectedTab == TabButton then return end
            Library:Tween(TabImage, TWEEN_FAST, { ImageColor3 = FromRGB(255, 255, 255) })
            for _, c in ipairs(TabButton:GetChildren()) do
                if c:IsA("TextLabel") then
                    Library:Tween(c, TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
                end
            end
        end)

        TabButton.MouseLeave:Connect(function()
            if selectedTab == TabButton then return end
            Library:Tween(TabImage, TWEEN_FAST, { ImageColor3 = FromRGB(100, 100, 100) })
            for _, c in ipairs(TabButton:GetChildren()) do
                if c:IsA("TextLabel") then
                    Library:Tween(c, TWEEN_FAST, { TextColor3 = FromRGB(100, 100, 100) })
                end
            end
        end)

        -- ── Section (sub-page inside a tab) ─────────────
        local isFirstSection = true
        local numSections    = 0
        local selectedSection = nil

        Page.Items = { Tab = Tab, TabSections = TabSections, TabFrames = TabFrames }

        -- ─────────────────────────────────────────────────
        -- Page:Section  (like Utopia's Library.Pages.Section)
        -- ─────────────────────────────────────────────────
        function Page:Section(data3)
            data3 = data3 or {}
            local Section = {
                Window   = Window,
                Page     = Page,
                Name     = data3.Name or data3.name or "Section",
                Items    = {},
            }

            numSections += 1
            local sectionName = Section.Name

            local SectionButton = create("TextButton", {
                BackgroundTransparency = 1,
                Size         = UDim2New(1 / numSections, 0, 1, 0),
                Font         = Enum.Font.Ubuntu,
                Text         = sectionName,
                TextColor3   = FromRGB(100, 100, 100),
                TextSize     = 15,
            }, TabSections)

            -- Resize all section buttons equally
            for _, sb in ipairs(TabSections:GetChildren()) do
                if sb:IsA("TextButton") then
                    sb.Size = UDim2New(1 / numSections, 0, 1, 0)
                end
            end

            SectionButton.MouseEnter:Connect(function()
                if selectedSection == SectionButton then return end
                Library:Tween(SectionButton, TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
            end)
            SectionButton.MouseLeave:Connect(function()
                if selectedSection == SectionButton then return end
                Library:Tween(SectionButton, TWEEN_FAST, { TextColor3 = FromRGB(100, 100, 100) })
            end)

            -- Underline decoration
            local SectionDecoration = create("Frame", {
                BackgroundColor3 = FromRGB(255, 255, 255),
                BorderSizePixel  = 0,
                Position = UDim2New(0, 0, 0, 27),
                Size     = UDim2New(1, 0, 0, 1),
                Visible  = false,
            }, SectionButton)

            create("UIGradient", {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0,   FromRGB(32,  33,  38)),
                    ColorSequenceKeypoint.new(0.5, FromRGB(81,  97, 243)),
                    ColorSequenceKeypoint.new(1,   FromRGB(32,  33,  38)),
                }),
            }, SectionDecoration)

            -- Content frame (Left/Right columns)
            local SectionFrame = create("Frame", {
                BackgroundTransparency = 1,
                Size    = UDim2New(1, 0, 1, 0),
                Visible = false,
            }, TabFrames)

            local Left = create("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2New(0, 8, 0, 14),
                Size     = UDim2New(0, 282, 0, 395),
            }, SectionFrame)
            create("UIListLayout", {
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                SortOrder           = Enum.SortOrder.LayoutOrder,
                Padding             = UDimNew(0, 12),
            }, Left)

            local Right = create("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2New(0, 298, 0, 14),
                Size     = UDim2New(0, 282, 0, 395),
            }, SectionFrame)
            create("UIListLayout", {
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                SortOrder           = Enum.SortOrder.LayoutOrder,
                Padding             = UDimNew(0, 12),
            }, Right)

            SectionButton.MouseButton1Down:Connect(function()
                for _, sb in ipairs(TabSections:GetChildren()) do
                    if sb:IsA("TextButton") then
                        Library:Tween(sb, TWEEN_FAST, { TextColor3 = FromRGB(100, 100, 100) })
                        sb.SectionDecoration.Visible = false
                    end
                end
                for _, sf in ipairs(TabFrames:GetChildren()) do
                    if sf:IsA("Frame") then sf.Visible = false end
                end
                selectedSection           = SectionButton
                SectionFrame.Visible      = true
                SectionDecoration.Visible = true
                Library:Tween(SectionButton, TWEEN_FAST, { TextColor3 = FromRGB(84, 101, 255) })
            end)

            if isFirstSection then
                isFirstSection        = false
                selectedSection       = SectionButton
                SectionButton.TextColor3  = FromRGB(84, 101, 255)
                SectionDecoration.Visible = true
                SectionFrame.Visible      = true
            end

            Section.Items = { Left = Left, Right = Right, SectionFrame = SectionFrame }

            -- ─────────────────────────────────────────────
            -- Subsector helper (maps Side → Left or Right)
            -- ─────────────────────────────────────────────
            local function getColumn(side)
                -- side: 1 or "Left" → Left column; 2 or "Right" → Right column
                if side == 2 or side == "Right" then return Right end
                return Left
            end

            -- =============================================
            -- Section element factories  (Utopia API)
            -- =============================================

            -- ── Toggle ───────────────────────────────────
            function Section:Toggle(data4)
                data4 = data4 or {}
                local Toggle = {
                    Window   = Window,
                    Page     = Page,
                    Section  = Section,
                    Name     = data4.Name or data4.name or "Toggle",
                    Flag     = data4.Flag or data4.flag or Library:NextFlag(),
                    Value    = false,
                    Keybinds = {},
                }

                local column  = getColumn(data4.Side or data4.side or 1)
                local default = data4.Default ~= nil and data4.Default or (data4.default ~= nil and data4.default or false)

                -- Container row
                local Border = create("Frame", {
                    BackgroundColor3 = FromRGB(5, 5, 5),
                    BorderColor3     = FromRGB(30, 30, 30),
                    Size             = UDim2New(1, 0, 0, 18),
                }, column)

                local Container = create("Frame", {
                    BackgroundColor3 = FromRGB(10, 10, 10),
                    BorderSizePixel  = 0,
                    Position         = UDim2New(0, 1, 0, 1),
                    Size             = UDim2New(1, -2, 1, -2),
                }, Border)

                local ToggleButton = create("TextButton", {
                    BackgroundTransparency = 1,
                    Size   = UDim2New(1, 0, 1, 0),
                    Text   = "",
                }, Container)

                local ToggleFrame = create("Frame", {
                    AnchorPoint      = Vector2New(0, 0.5),
                    BackgroundColor3 = FromRGB(30, 30, 30),
                    BorderColor3     = FromRGB(0, 0, 0),
                    Position         = UDim2New(0, 9, 0.5, 0),
                    Size             = UDim2New(0, 9, 0, 9),
                }, ToggleButton)

                local ToggleText = create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position       = UDim2New(0, 27, 0, 5),
                    Size           = UDim2New(0, 200, 0, 9),
                    Font           = Enum.Font.Ubuntu,
                    Text           = Toggle.Name,
                    TextColor3     = FromRGB(150, 150, 150),
                    TextSize       = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }, ToggleButton)

                local mouseIn = false

                local function applyVisual(v)
                    if v then
                        Library:Tween(ToggleFrame, TWEEN_FAST, { BackgroundColor3 = FromRGB(84, 101, 255) })
                        Library:Tween(ToggleText,  TWEEN_FAST, { TextColor3       = FromRGB(255, 255, 255) })
                    else
                        Library:Tween(ToggleFrame, TWEEN_FAST, { BackgroundColor3 = FromRGB(30, 30, 30) })
                        if not mouseIn then
                            Library:Tween(ToggleText, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                        end
                    end
                end

                function Toggle:Set(v)
                    Toggle.Value              = v
                    Library.Flags[Toggle.Flag] = Toggle.Value
                    applyVisual(v)
                    if data4.Callback and not Library.IsLoading then
                        Library:SafeCall(data4.Callback, Toggle.Value)
                    elseif data4.callback and not Library.IsLoading then
                        Library:SafeCall(data4.callback, Toggle.Value)
                    end
                end

                function Toggle:Get()        return Toggle.Value end
                function Toggle:SetVisibility(b) Border.Visible = b end

                Library.SetFlags[Toggle.Flag] = function(v) Toggle:Set(v) end

                ToggleButton.MouseEnter:Connect(function()
                    mouseIn = true
                    if not Toggle.Value then
                        Library:Tween(ToggleText, TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
                    end
                end)
                ToggleButton.MouseLeave:Connect(function()
                    mouseIn = false
                    if not Toggle.Value then
                        Library:Tween(ToggleText, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                    end
                end)
                ToggleButton.MouseButton1Down:Connect(function()
                    Toggle:Set(not Toggle.Value)
                end)

                if default then Toggle:Set(true) else Toggle:Set(false) end

                -- ── Toggle:Keybind ────────────────────────
                function Toggle:Keybind(kb)
                    kb = kb or {}
                    local Keybind = {
                        Flag     = kb.Flag or kb.flag or Library:NextFlag(),
                        Name     = kb.Name or "Keybind",
                        Mode     = kb.Mode or "Toggle",
                        Key      = nil,
                        Value    = "[None]",
                        Toggled  = false,
                        IsOpen   = false,
                        Picking  = false,
                    }

                    -- [KEY] label
                    local KeyButton = create("TextButton", {
                        BackgroundTransparency = 1,
                        AnchorPoint      = Vector2New(1, 0),
                        Position         = UDim2New(0, 265, 0, 0),
                        Size             = UDim2New(0, 56, 0, 18),
                        AutomaticSize    = Enum.AutomaticSize.X,
                        Font             = Enum.Font.Ubuntu,
                        Text             = "[ NONE ]",
                        TextColor3       = FromRGB(150, 150, 150),
                        TextSize         = 14,
                        TextXAlignment   = Enum.TextXAlignment.Right,
                    }, ToggleButton)

                    -- Mode popup
                    local KeybindFrame = create("Frame", {
                        BackgroundColor3 = FromRGB(10, 10, 10),
                        BorderColor3     = FromRGB(30, 30, 30),
                        Position         = UDim2New(1, 5, 0, 3),
                        Size             = UDim2New(0, 55, 0, 75),
                        Visible          = false,
                        ZIndex           = 2,
                    }, KeyButton)

                    create("UIListLayout", {
                        HorizontalAlignment = Enum.HorizontalAlignment.Center,
                        SortOrder           = Enum.SortOrder.LayoutOrder,
                    }, KeybindFrame)

                    local modeButtons = {}
                    for _, modeName in ipairs({"Always", "Hold", "Toggle"}) do
                        local mb = create("TextButton", {
                            BackgroundTransparency = 1,
                            Size       = UDim2New(1, 0, 0, 25),
                            Font       = Enum.Font.Ubuntu,
                            Text       = modeName,
                            TextColor3 = modeName == Keybind.Mode
                                            and FromRGB(84, 101, 255)
                                            or  FromRGB(150, 150, 150),
                            TextSize   = 14,
                            ZIndex     = 2,
                        }, KeybindFrame)
                        modeButtons[modeName] = mb
                    end

                    local debounce = false

                    local function updateModeUI()
                        for name, mb in pairs(modeButtons) do
                            Library:Tween(mb, TWEEN_FAST, {
                                TextColor3 = name == Keybind.Mode
                                    and FromRGB(84, 101, 255)
                                    or  FromRGB(150, 150, 150)
                            })
                        end
                    end

                    local function setKeyText(keyName)
                        local display = keyName and ("[ "..keyName:upper().." ]") or "[ NONE ]"
                        KeyButton.Text = display
                        KeyButton.Size = UDim2New(0,
                            getTextSize(display, 14, Enum.Font.Ubuntu, Vector2New(700, 20)).X + 3,
                            0, 18)
                    end

                    function Keybind:SetOpen(b)
                        Keybind.IsOpen      = b
                        KeybindFrame.Visible = b
                        if b then
                            debounce = true
                            KeybindFrame.ZIndex = 16
                            task.wait(0.1)
                            debounce = false
                        end
                    end

                    function Keybind:Set(v)
                        if type(v) == "table" then
                            -- config load: {Key=..., Mode=...}
                            local rawKey  = v.Key
                            local keyName = rawKey and tostring(rawKey):gsub("Enum%.KeyCode%.", ""):gsub("Enum%.UserInputType%.", "") or nil
                            if keyName == "Backspace" or keyName == "Unknown" then keyName = nil end
                            Keybind.Key   = rawKey and tostring(rawKey) or nil
                            setKeyText(keyName)
                            if v.Mode then
                                Keybind.Mode = v.Mode
                                updateModeUI()
                            end
                        elseif typeof(v) == "EnumItem" then
                            local kName = v.Name
                            if kName == "Backspace" or kName == "Escape" or kName == "Unknown" then
                                Keybind.Key = nil
                                setKeyText(nil)
                            else
                                Keybind.Key = tostring(v)
                                setKeyText(kName)
                            end
                        end
                        Keybind.Picking = false
                        Library.Flags[Keybind.Flag] = { Mode = Keybind.Mode, Key = Keybind.Key, Value = Keybind.Toggled }
                        if kb.Callback and not Library.IsLoading then Library:SafeCall(kb.Callback, Keybind.Toggled) end
                    end

                    function Keybind:Get() return Keybind.Toggled, Keybind.Key, Keybind.Mode end
                    function Keybind:SetVisibility(b) KeyButton.Visible = b end

                    Library.SetFlags[Keybind.Flag] = function(v) Keybind:Set(v) end

                    -- Click → bind key
                    KeyButton.MouseButton1Click:Connect(function()
                        if Keybind.Picking then return end
                        Keybind.Picking    = true
                        KeyButton.Text     = "[ ... ]"
                        local conn
                        conn = Library:Connect(UserInputService.InputBegan, function(input)
                            if input.UserInputType == Enum.UserInputType.Keyboard then
                                Keybind:Set(input.KeyCode)
                            else
                                Keybind:Set(input.UserInputType)
                            end
                            conn.Connection:Disconnect()
                        end)
                    end)

                    -- Right-click → mode popup
                    KeyButton.MouseButton2Down:Connect(function()
                        Keybind:SetOpen(not Keybind.IsOpen)
                    end)

                    -- Mode buttons
                    for modeName, mb in pairs(modeButtons) do
                        mb.MouseButton1Down:Connect(function()
                            Keybind.Mode = modeName
                            Keybind.IsOpen = false
                            KeybindFrame.Visible = false
                            if Keybind.Mode == "Always" then Keybind.Toggled = true
                            else Keybind.Toggled = false end
                            Library.Flags[Keybind.Flag] = { Mode = Keybind.Mode, Key = Keybind.Key, Value = Keybind.Toggled }
                            updateModeUI()
                            if kb.Callback and not Library.IsLoading then Library:SafeCall(kb.Callback, Keybind.Toggled) end
                        end)
                    end

                    -- Close popup when clicking outside
                    Library:Connect(UserInputService.InputBegan, function(input)
                        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and
                           input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
                        if debounce then return end
                        if not Keybind.IsOpen then return end
                        if Library:IsMouseOverFrame(KeybindFrame) then return end
                        Keybind:SetOpen(false)
                    end)

                    -- Activate on keypress
                    Library:Connect(UserInputService.InputBegan, function(input)
                        if UserInputService:GetFocusedTextBox() then return end
                        local k = tostring(input.KeyCode) ~= "Enum.KeyCode.Unknown"
                            and tostring(input.KeyCode)
                            or tostring(input.UserInputType)
                        if k == Keybind.Key then
                            if Keybind.Mode == "Toggle" then
                                Keybind.Toggled = not Keybind.Toggled
                            elseif Keybind.Mode == "Hold" then
                                Keybind.Toggled = true
                            elseif Keybind.Mode == "Always" then
                                Keybind.Toggled = true
                            end
                            Library.Flags[Keybind.Flag] = { Mode = Keybind.Mode, Key = Keybind.Key, Value = Keybind.Toggled }
                            if kb.Callback and not Library.IsLoading then Library:SafeCall(kb.Callback, Keybind.Toggled) end
                        end
                    end)

                    Library:Connect(UserInputService.InputEnded, function(input)
                        local k = tostring(input.KeyCode) ~= "Enum.KeyCode.Unknown"
                            and tostring(input.KeyCode)
                            or tostring(input.UserInputType)
                        if k == Keybind.Key and Keybind.Mode == "Hold" then
                            Keybind.Toggled = false
                            Library.Flags[Keybind.Flag] = { Mode = Keybind.Mode, Key = Keybind.Key, Value = Keybind.Toggled }
                            if kb.Callback and not Library.IsLoading then Library:SafeCall(kb.Callback, Keybind.Toggled) end
                        end
                    end)

                    if kb.Default then Keybind:Set({ Key = kb.Default, Mode = kb.Mode or "Toggle" }) end

                    -- Return Toggle so chains work:  Toggle:Keybind(...)  (no chaining needed but supported)
                    return Toggle
                end

                -- ── Toggle:Colorpicker ────────────────────
                function Toggle:Colorpicker(cp)
                    -- lightweight colour button (swatch) attached to the toggle row
                    cp = cp or {}
                    local CP = {
                        Flag    = cp.Flag or Library:NextFlag(),
                        Color   = cp.Default or FromRGB(255, 255, 255),
                        IsOpen  = false,
                    }

                    local Swatch = create("TextButton", {
                        AnchorPoint      = Vector2New(1, 0.5),
                        BackgroundColor3 = CP.Color,
                        BorderColor3     = FromRGB(0, 0, 0),
                        Position         = UDim2New(1, -2, 0.5, 0),
                        Size             = UDim2New(0, 25, 0, 11),
                        Text             = "",
                        AutoButtonColor  = false,
                    }, ToggleButton)

                    local ColorFrame = create("Frame", {
                        BackgroundColor3 = FromRGB(10, 10, 10),
                        BorderColor3     = FromRGB(0, 0, 0),
                        Position         = UDim2New(1, 5, 0, 0),
                        Size             = UDim2New(0, 200, 0, 170),
                        Visible          = false,
                        ZIndex           = 2,
                    }, Swatch)

                    local ColorPicker = create("ImageButton", {
                        BackgroundColor3 = FromRGB(255, 255, 255),
                        BorderColor3     = FromRGB(0, 0, 0),
                        Position         = UDim2New(0, 40, 0, 10),
                        Size             = UDim2New(0, 150, 0, 150),
                        AutoButtonColor  = false,
                        Image            = "rbxassetid://4155801252",
                        ImageColor3      = FromRGB(255, 0, 4),
                        ZIndex           = 2,
                    }, ColorFrame)

                    local ColorPick = create("Frame", {
                        BackgroundColor3 = FromRGB(255, 255, 255),
                        BorderColor3     = FromRGB(0, 0, 0),
                        Size             = UDim2New(0, 1, 0, 1),
                        ZIndex           = 2,
                    }, ColorPicker)

                    local HuePicker = create("TextButton", {
                        BackgroundColor3 = FromRGB(255, 255, 255),
                        BorderColor3     = FromRGB(0, 0, 0),
                        Position         = UDim2New(0, 10, 0, 10),
                        Size             = UDim2New(0, 20, 0, 150),
                        ZIndex           = 2,
                        AutoButtonColor  = false,
                        Text             = "",
                    }, ColorFrame)

                    create("UIGradient", {
                        Rotation = 90,
                        Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0.00, FromRGB(255, 0,   0)),
                            ColorSequenceKeypoint.new(0.17, FromRGB(255, 0, 255)),
                            ColorSequenceKeypoint.new(0.33, FromRGB(0,   0, 255)),
                            ColorSequenceKeypoint.new(0.50, FromRGB(0, 255, 255)),
                            ColorSequenceKeypoint.new(0.67, FromRGB(0, 255,   0)),
                            ColorSequenceKeypoint.new(0.83, FromRGB(255, 255,   0)),
                            ColorSequenceKeypoint.new(1.00, FromRGB(255, 0,   0)),
                        }),
                    }, HuePicker)

                    local HuePick = create("Frame", {
                        BackgroundColor3 = FromRGB(255, 255, 255),
                        BorderColor3     = FromRGB(0, 0, 0),
                        Size             = UDim2New(1, 0, 0, 1),
                        ZIndex           = 2,
                    }, HuePicker)

                    local col = { h = 0, s = 1, v = 1 }

                    local function updateColor()
                        local c = FromHSV(col.h, col.s, col.v)
                        CP.Color              = c
                        Swatch.BackgroundColor3 = c
                        Library.Flags[CP.Flag]  = c
                        ColorPicker.ImageColor3  = FromHSV(col.h, 1, 1)
                        if cp.Callback and not Library.IsLoading then Library:SafeCall(cp.Callback, c) end
                    end

                    local function slideColor()
                        local cx = MathClamp(Mouse.X - ColorPicker.AbsolutePosition.X, 0, ColorPicker.AbsoluteSize.X)
                        local cy = MathClamp(Mouse.Y - ColorPicker.AbsolutePosition.Y, 0, ColorPicker.AbsoluteSize.Y)
                        ColorPick.Position = UDim2New(cx / ColorPicker.AbsoluteSize.X, 0, cy / ColorPicker.AbsoluteSize.Y, 0)
                        col.s = 1 - cx / ColorPicker.AbsoluteSize.X
                        col.v = 1 - cy / ColorPicker.AbsoluteSize.Y
                        updateColor()
                    end

                    local function slideHue()
                        local y = MathClamp(Mouse.Y - HuePicker.AbsolutePosition.Y, 0, 148)
                        HuePick.Position    = UDim2New(0, 0, 0, y)
                        col.h               = 1 - y / 148
                        updateColor()
                    end

                    -- Connect color picker
                    ColorPicker.MouseButton1Down:Connect(function()
                        slideColor()
                        local mc = Mouse.Move:Connect(slideColor)
                        local rc; rc = UserInputService.InputEnded:Connect(function(i)
                            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                                slideColor(); mc:Disconnect(); rc:Disconnect()
                            end
                        end)
                    end)

                    HuePicker.MouseButton1Down:Connect(function()
                        slideHue()
                        local mc = Mouse.Move:Connect(slideHue)
                        local rc; rc = UserInputService.InputEnded:Connect(function(i)
                            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                                slideHue(); mc:Disconnect(); rc:Disconnect()
                            end
                        end)
                    end)

                    Swatch.MouseButton1Down:Connect(function()
                        ColorFrame.Visible = not ColorFrame.Visible
                    end)

                    local inFrame = false
                    ColorFrame.MouseEnter:Connect(function() inFrame = true end)
                    ColorFrame.MouseLeave:Connect(function() inFrame = false end)
                    UserInputService.InputBegan:Connect(function(input)
                        if (input.UserInputType == Enum.UserInputType.MouseButton1
                        or  input.UserInputType == Enum.UserInputType.MouseButton2)
                        and ColorFrame.Visible and not inFrame then
                            ColorFrame.Visible = false
                        end
                    end)

                    function CP:Set(color, _alpha)
                        if type(color) == "string" then color = Color3.fromHex(color) end
                        CP.Color = color
                        col.h, col.s, col.v = color:ToHSV()
                        Swatch.BackgroundColor3  = color
                        ColorPicker.ImageColor3  = FromHSV(col.h, 1, 1)
                        ColorPick.Position       = UDim2New(1 - col.s, 0, 1 - col.v, 0)
                        HuePick.Position         = UDim2New(0, 0, 1 - col.h, -1)
                        Library.Flags[CP.Flag]   = color
                        if cp.Callback and not Library.IsLoading then Library:SafeCall(cp.Callback, color) end
                    end

                    function CP:Get()            return CP.Color end
                    function CP:SetVisibility(b) Swatch.Visible = b end

                    Library.SetFlags[CP.Flag] = function(v) CP:Set(v) end

                    if cp.Default then CP:Set(cp.Default) end

                    return CP
                end

                return Toggle
            end

            -- ── Button ───────────────────────────────────
            function Section:Button(data4)
                data4 = data4 or {}
                local Button = {
                    Window  = Window,
                    Page    = Page,
                    Section = Section,
                    Name    = data4.Name or data4.name or "Button",
                }

                local column = getColumn(data4.Side or data4.side or 1)

                local Border = create("Frame", {
                    BackgroundColor3 = FromRGB(5, 5, 5),
                    BorderColor3     = FromRGB(30, 30, 30),
                    Size             = UDim2New(1, 0, 0, 30),
                }, column)

                local Btn = create("TextButton", {
                    AnchorPoint      = Vector2New(0.5, 0.5),
                    BackgroundColor3 = FromRGB(25, 25, 25),
                    BorderColor3     = FromRGB(0, 0, 0),
                    Position         = UDim2New(0.5, 0, 0.5, 0),
                    Size             = UDim2New(0, 215, 0, 20),
                    AutoButtonColor  = false,
                    Font             = Enum.Font.Ubuntu,
                    Text             = Button.Name,
                    TextColor3       = FromRGB(150, 150, 150),
                    TextSize         = 14,
                }, Border)

                Btn.MouseEnter:Connect(function()
                    Library:Tween(Btn, TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
                end)
                Btn.MouseLeave:Connect(function()
                    Library:Tween(Btn, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                end)
                Btn.MouseButton1Down:Connect(function()
                    Btn.BorderColor3 = FromRGB(84, 101, 255)
                    Library:Tween(Btn, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        { BorderColor3 = FromRGB(0, 0, 0) })
                    local cb = data4.Callback or data4.callback
                    if cb then Library:SafeCall(cb) end
                end)

                function Button:SetVisibility(b) Border.Visible = b end
                return Button
            end

            -- ── Slider ───────────────────────────────────
            function Section:Slider(data4)
                data4 = data4 or {}
                local Slider = {
                    Window  = Window,
                    Page    = Page,
                    Section = Section,
                    Name    = data4.Name or data4.name or "Slider",
                    Flag    = data4.Flag or data4.flag or Library:NextFlag(),
                    Min     = data4.Min or data4.min or 0,
                    Max     = data4.Max or data4.max or 100,
                    Value   = 0,
                }
                local min = Slider.Min
                local max = Slider.Max
                local column = getColumn(data4.Side or data4.side or 1)

                local Border = create("Frame", {
                    BackgroundColor3 = FromRGB(5, 5, 5),
                    BorderColor3     = FromRGB(30, 30, 30),
                    Size             = UDim2New(1, 0, 0, 35),
                }, column)

                local Container = create("Frame", {
                    BackgroundColor3 = FromRGB(10, 10, 10),
                    BorderSizePixel  = 0,
                    Position         = UDim2New(0, 1, 0, 1),
                    Size             = UDim2New(1, -2, 1, -2),
                }, Border)

                local SliderText = create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position       = UDim2New(0, 9, 0, 6),
                    Size           = UDim2New(0, 200, 0, 9),
                    Font           = Enum.Font.Ubuntu,
                    Text           = Slider.Name,
                    TextColor3     = FromRGB(150, 150, 150),
                    TextSize       = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }, Container)

                local SliderButton = create("TextButton", {
                    BackgroundColor3 = FromRGB(25, 25, 25),
                    BorderColor3     = FromRGB(0, 0, 0),
                    Position         = UDim2New(0, 9, 0, 20),
                    Size             = UDim2New(0, 260, 0, 10),
                    AutoButtonColor  = false,
                    Text             = "",
                }, Container)

                local SliderFrame = create("Frame", {
                    BackgroundColor3 = FromRGB(255, 255, 255),
                    BorderSizePixel  = 0,
                    Size             = UDim2New(0, 0, 1, 0),
                }, SliderButton)

                create("UIGradient", {
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, FromRGB(79,  95, 239)),
                        ColorSequenceKeypoint.new(1, FromRGB(56,  67, 163)),
                    }),
                    Rotation = 90,
                }, SliderFrame)

                local SliderValue = create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position       = UDim2New(0, 69, 0, 6),
                    Size           = UDim2New(0, 200, 0, 9),
                    Font           = Enum.Font.Ubuntu,
                    Text           = "0",
                    TextColor3     = FromRGB(150, 150, 150),
                    TextSize       = 14,
                    TextXAlignment = Enum.TextXAlignment.Right,
                }, Container)

                local suffix   = data4.Suffix or data4.suffix or ""
                local decimals = data4.Decimals or data4.decimals or 1

                local function computeVal()
                    local x   = MathClamp(Mouse.X - SliderButton.AbsolutePosition.X, 0, 260)
                    local raw = ((max - min) / 260) * x + min
                    local m   = 1 / (decimals or 1)
                    return MathFloor(raw * m) / m
                end

                function Slider:Set(v)
                    v = MathClamp(v, min, max)
                    Slider.Value              = v
                    Library.Flags[Slider.Flag] = v
                    local pct = (v - min) / (max - min)
                    SliderFrame.Size  = UDim2New(pct, 0, 1, 0)
                    SliderValue.Text  = tostring(v) .. suffix
                    if data4.Callback and not Library.IsLoading then Library:SafeCall(data4.Callback, v)
                    elseif data4.callback and not Library.IsLoading then Library:SafeCall(data4.callback, v) end
                end

                function Slider:Get()           return Slider.Value end
                function Slider:SetVisibility(b) Border.Visible = b end

                Library.SetFlags[Slider.Flag] = function(v) Slider:Set(v) end

                local isSliding = false
                local mouseIn   = false

                Container.MouseEnter:Connect(function()
                    mouseIn = true
                    Library:Tween(SliderText,  TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
                    Library:Tween(SliderValue, TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
                end)
                Container.MouseLeave:Connect(function()
                    mouseIn = false
                    if not isSliding then
                        Library:Tween(SliderText,  TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                        Library:Tween(SliderValue, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                    end
                end)

                SliderButton.MouseButton1Down:Connect(function()
                    isSliding = true
                    Slider:Set(computeVal())
                    local mc = Mouse.Move:Connect(function() Slider:Set(computeVal()) end)
                    local rc; rc = UserInputService.InputEnded:Connect(function(i)
                        if i.UserInputType == Enum.UserInputType.MouseButton1 then
                            Slider:Set(computeVal())
                            isSliding = false
                            if not mouseIn then
                                Library:Tween(SliderText,  TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                                Library:Tween(SliderValue, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                            end
                            mc:Disconnect(); rc:Disconnect()
                        end
                    end)
                end)

                local def = data4.Default or data4.default
                if def ~= nil then Slider:Set(def) else Slider:Set(min) end

                return Slider
            end

            -- ── Dropdown ──────────────────────────────────
            function Section:Dropdown(data4)
                data4 = data4 or {}
                local Dropdown = {
                    Window   = Window,
                    Page     = Page,
                    Section  = Section,
                    Name     = data4.Name or data4.name or "Dropdown",
                    Flag     = data4.Flag or data4.flag or Library:NextFlag(),
                    Value    = nil,
                    IsOpen   = false,
                    Options  = {},
                    Multi    = data4.Multi or data4.multi or false,
                }

                local column  = getColumn(data4.Side or data4.side or 1)
                local options = data4.Items or data4.items or data4.options or {}

                local Border = create("Frame", {
                    BackgroundColor3 = FromRGB(5, 5, 5),
                    BorderColor3     = FromRGB(30, 30, 30),
                    Size             = UDim2New(1, 0, 0, 45),
                }, column)

                local Container = create("Frame", {
                    BackgroundColor3 = FromRGB(10, 10, 10),
                    BorderSizePixel  = 0,
                    Position         = UDim2New(0, 1, 0, 1),
                    Size             = UDim2New(1, -2, 1, -2),
                }, Border)

                local DropLabel = create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position       = UDim2New(0, 9, 0, 6),
                    Size           = UDim2New(0, 200, 0, 9),
                    Font           = Enum.Font.Ubuntu,
                    Text           = Dropdown.Name,
                    TextColor3     = FromRGB(150, 150, 150),
                    TextSize       = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }, Container)

                local DropButton = create("TextButton", {
                    BackgroundColor3 = FromRGB(25, 25, 25),
                    BorderColor3     = FromRGB(0, 0, 0),
                    Position         = UDim2New(0, 9, 0, 20),
                    Size             = UDim2New(0, 260, 0, 20),
                    AutoButtonColor  = false,
                    Text             = "",
                }, Container)

                local DropBtnText = create("TextLabel", {
                    BackgroundTransparency = 1,
                    Position       = UDim2New(0, 6, 0, 0),
                    Size           = UDim2New(0, 250, 1, 0),
                    Font           = Enum.Font.Ubuntu,
                    Text           = "--",
                    TextColor3     = FromRGB(150, 150, 150),
                    TextSize       = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                }, DropButton)

                local numOpts = #options
                local scrollH = numOpts >= 4 and 80 or (numOpts * 20)

                local DropScroll = create("ScrollingFrame", {
                    Active           = true,
                    BackgroundColor3 = FromRGB(25, 25, 25),
                    BorderColor3     = FromRGB(0, 0, 0),
                    Position         = UDim2New(0, 9, 0, 41),
                    Size             = UDim2New(0, 260, 0, scrollH),
                    CanvasSize       = UDim2New(0, 0, 0, numOpts * 20),
                    ScrollBarThickness = 2,
                    Visible          = false,
                    ZIndex           = 2,
                }, Container)

                create("UIListLayout", {
                    HorizontalAlignment = Enum.HorizontalAlignment.Center,
                    SortOrder           = Enum.SortOrder.LayoutOrder,
                }, DropScroll)

                local inDrop  = false
                local inDrop2 = false

                DropButton.MouseButton1Down:Connect(function()
                    DropScroll.Visible = not DropScroll.Visible
                    local open = DropScroll.Visible
                    local col3 = open and FromRGB(255, 255, 255) or FromRGB(150, 150, 150)
                    Library:Tween(DropLabel,   TWEEN_FAST, { TextColor3 = col3 })
                    Library:Tween(DropBtnText, TWEEN_FAST, { TextColor3 = col3 })
                end)
                Container.MouseEnter:Connect(function() inDrop  = true  end)
                Container.MouseLeave:Connect(function() inDrop  = false end)
                DropScroll.MouseEnter:Connect(function() inDrop2 = true  end)
                DropScroll.MouseLeave:Connect(function() inDrop2 = false end)

                Library:Connect(UserInputService.InputBegan, function(input)
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1
                    and input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
                    if DropScroll.Visible and not inDrop and not inDrop2 then
                        DropScroll.Visible = false
                        DropScroll.CanvasPosition = Vector2New(0, 0)
                        Library:Tween(DropLabel,   TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                        Library:Tween(DropBtnText, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                    end
                end)

                local function refreshText()
                    if Dropdown.Multi then
                        local v = Dropdown.Value
                        DropBtnText.Text = (type(v) == "table" and #v > 0)
                            and table.concat(v, ", ") or "--"
                    else
                        DropBtnText.Text = Dropdown.Value or "--"
                    end
                end

                local function addOption(optName)
                    local Btn = create("TextButton", {
                        BackgroundColor3 = FromRGB(25, 25, 25),
                        BorderColor3     = FromRGB(0, 0, 0),
                        BorderSizePixel  = 0,
                        Size             = UDim2New(1, 0, 0, 20),
                        AutoButtonColor  = false,
                        Text             = "",
                        ZIndex           = 2,
                    }, DropScroll)

                    local BtnText = create("TextLabel", {
                        BackgroundTransparency = 1,
                        Position       = UDim2New(0, 8, 0, 0),
                        Size           = UDim2New(0, 245, 1, 0),
                        Font           = Enum.Font.Ubuntu,
                        Text           = optName,
                        TextColor3     = FromRGB(150, 150, 150),
                        TextSize       = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        ZIndex         = 2,
                    }, Btn)

                    local Deco = create("Frame", {
                        BackgroundColor3 = FromRGB(84, 101, 255),
                        BorderSizePixel  = 0,
                        Size             = UDim2New(0, 1, 1, 0),
                        Visible          = false,
                        ZIndex           = 2,
                    }, Btn)

                    Btn.MouseEnter:Connect(function()
                        Library:Tween(BtnText, TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
                        Deco.Visible = true
                    end)
                    Btn.MouseLeave:Connect(function()
                        if Dropdown.Multi then
                            if not TableFind(Dropdown.Value or {}, optName) then
                                Library:Tween(BtnText, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                                Deco.Visible = false
                            end
                        elseif Dropdown.Value ~= optName then
                            Library:Tween(BtnText, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                            Deco.Visible = false
                        end
                    end)
                    Btn.MouseButton1Down:Connect(function()
                        DropScroll.Visible = false
                        Library:Tween(DropLabel,   TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                        Library:Tween(DropBtnText, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })

                        if Dropdown.Multi then
                            if not Dropdown.Value then Dropdown.Value = {} end
                            local idx = TableFind(Dropdown.Value, optName)
                            if idx then TableRemove(Dropdown.Value, idx)
                            else TableInsert(Dropdown.Value, optName) end
                        else
                            Dropdown.Value = optName
                        end

                        Library.Flags[Dropdown.Flag] = Dropdown.Value
                        refreshText()

                        local cb = data4.Callback or data4.callback
                        if cb and not Library.IsLoading then Library:SafeCall(cb, Dropdown.Value) end
                    end)

                    Dropdown.Options[optName] = { Button = Btn, Text = BtnText, Deco = Deco }
                end

                for _, o in ipairs(options) do addOption(o) end

                function Dropdown:Set(v)
                    Dropdown.Value              = v
                    Library.Flags[Dropdown.Flag] = v
                    refreshText()
                    local cb = data4.Callback or data4.callback
                    if cb and not Library.IsLoading then Library:SafeCall(cb, v) end
                end

                function Dropdown:Get()             return Dropdown.Value end
                function Dropdown:SetVisibility(b)  Border.Visible = b    end
                function Dropdown:Add(o)            addOption(o)           end
                function Dropdown:Remove(o)
                    if Dropdown.Options[o] then
                        Dropdown.Options[o].Button:Destroy()
                        Dropdown.Options[o] = nil
                    end
                end
                function Dropdown:Refresh(list)
                    for k, d in pairs(Dropdown.Options) do
                        d.Button:Destroy()
                    end
                    Dropdown.Options = {}
                    for _, o in ipairs(list) do addOption(o) end
                end

                Library.SetFlags[Dropdown.Flag] = function(v) Dropdown:Set(v) end

                local def = data4.Default or data4.default
                if def ~= nil then Dropdown:Set(def) end

                return Dropdown
            end

            -- ── Label ─────────────────────────────────────
            function Section:Label(text, alignment)
                local Label = {
                    Window  = Window,
                    Page    = Page,
                    Section = Section,
                    Name    = text or "Label",
                }

                local column = getColumn(1)

                local Border = create("Frame", {
                    BackgroundColor3 = FromRGB(5, 5, 5),
                    BorderColor3     = FromRGB(30, 30, 30),
                    Size             = UDim2New(1, 0, 0, 18),
                }, column)

                local LblText = create("TextLabel", {
                    BackgroundTransparency = 1,
                    Size           = UDim2New(1, 0, 1, 0),
                    Font           = Enum.Font.Ubuntu,
                    Text           = text or "",
                    TextColor3     = FromRGB(150, 150, 150),
                    TextSize       = 14,
                    TextXAlignment = alignment == "Right" and Enum.TextXAlignment.Right
                                  or alignment == "Center" and Enum.TextXAlignment.Center
                                  or Enum.TextXAlignment.Left,
                    RichText       = true,
                }, Border)

                function Label:SetVisibility(b)  Border.Visible = b    end
                function Label:SetText(t)        LblText.Text   = t    end

                -- Labels can also host colour pickers (Utopia compat)
                function Label:Colorpicker(cp)
                    cp = cp or {}
                    -- reuse the Toggle colorpicker logic via a dummy toggle wrapper
                    local dummyToggle = { Name = cp.Name }
                    local cpBorder = Border  -- attach to this label's border
                    -- Inline compact version:
                    local CP = {
                        Flag  = cp.Flag or Library:NextFlag(),
                        Color = cp.Default or FromRGB(255, 255, 255),
                    }
                    local Swatch = create("TextButton", {
                        AnchorPoint      = Vector2New(1, 0.5),
                        BackgroundColor3 = CP.Color,
                        BorderColor3     = FromRGB(0, 0, 0),
                        Position         = UDim2New(1, -2, 0.5, 0),
                        Size             = UDim2New(0, 25, 0, 11),
                        Text             = "",
                        AutoButtonColor  = false,
                    }, Border)

                    function CP:Set(color)
                        CP.Color                = color
                        Swatch.BackgroundColor3 = color
                        Library.Flags[CP.Flag]   = color
                        if cp.Callback and not Library.IsLoading then Library:SafeCall(cp.Callback, color) end
                    end
                    function CP:Get()            return CP.Color  end
                    function CP:SetVisibility(b) Swatch.Visible = b end

                    Library.SetFlags[CP.Flag] = function(v) CP:Set(v) end
                    if cp.Default then CP:Set(cp.Default) end
                    return CP
                end

                -- Labels can also host keybinds (Utopia compat)
                function Label:Keybind(kb)
                    -- delegate to a minimal keybind (same logic as Toggle:Keybind but standalone)
                    kb = kb or {}
                    local Keybind = {
                        Flag    = kb.Flag or Library:NextFlag(),
                        Key     = nil,
                        Mode    = kb.Mode or "Toggle",
                        Toggled = false,
                    }

                    local KeyButton = create("TextButton", {
                        AnchorPoint      = Vector2New(1, 0.5),
                        BackgroundTransparency = 1,
                        Position         = UDim2New(1, -2, 0.5, 0),
                        Size             = UDim2New(0, 56, 0, 18),
                        Font             = Enum.Font.Ubuntu,
                        Text             = "[ NONE ]",
                        TextColor3       = FromRGB(150, 150, 150),
                        TextSize         = 14,
                        TextXAlignment   = Enum.TextXAlignment.Right,
                    }, Border)

                    function Keybind:Set(v)
                        if type(v) == "table" then
                            Keybind.Key  = v.Key  and tostring(v.Key)  or nil
                            if v.Mode then Keybind.Mode = v.Mode end
                        elseif typeof(v) == "EnumItem" then
                            local kn = v.Name
                            if kn == "Backspace" or kn == "Escape" or kn == "Unknown" then
                                Keybind.Key = nil
                            else
                                Keybind.Key = tostring(v)
                            end
                        end
                        local display = Keybind.Key and ("[ "..Keybind.Key:gsub("Enum%.KeyCode%.",""):gsub("Enum%.UserInputType%.",""):upper().." ]") or "[ NONE ]"
                        KeyButton.Text = display
                        Library.Flags[Keybind.Flag] = { Mode = Keybind.Mode, Key = Keybind.Key, Value = Keybind.Toggled }
                    end
                    function Keybind:Get()            return Keybind.Toggled, Keybind.Key, Keybind.Mode end
                    function Keybind:SetVisibility(b) KeyButton.Visible = b end

                    Library.SetFlags[Keybind.Flag] = function(v) Keybind:Set(v) end

                    KeyButton.MouseButton1Click:Connect(function()
                        KeyButton.Text = "[ ... ]"
                        local conn; conn = Library:Connect(UserInputService.InputBegan, function(input)
                            if input.UserInputType == Enum.UserInputType.Keyboard then
                                Keybind:Set(input.KeyCode)
                            else
                                Keybind:Set(input.UserInputType)
                            end
                            conn.Connection:Disconnect()
                        end)
                    end)

                    Library:Connect(UserInputService.InputBegan, function(input)
                        if UserInputService:GetFocusedTextBox() then return end
                        local k = tostring(input.KeyCode) ~= "Enum.KeyCode.Unknown"
                            and tostring(input.KeyCode) or tostring(input.UserInputType)
                        if k == Keybind.Key then
                            if Keybind.Mode == "Toggle" then Keybind.Toggled = not Keybind.Toggled
                            elseif Keybind.Mode == "Hold" then Keybind.Toggled = true
                            elseif Keybind.Mode == "Always" then Keybind.Toggled = true end
                            Library.Flags[Keybind.Flag] = { Mode = Keybind.Mode, Key = Keybind.Key, Value = Keybind.Toggled }
                            if kb.Callback and not Library.IsLoading then Library:SafeCall(kb.Callback, Keybind.Toggled) end
                        end
                    end)
                    Library:Connect(UserInputService.InputEnded, function(input)
                        local k = tostring(input.KeyCode) ~= "Enum.KeyCode.Unknown"
                            and tostring(input.KeyCode) or tostring(input.UserInputType)
                        if k == Keybind.Key and Keybind.Mode == "Hold" then
                            Keybind.Toggled = false
                            Library.Flags[Keybind.Flag] = { Mode = Keybind.Mode, Key = Keybind.Key, Value = Keybind.Toggled }
                            if kb.Callback and not Library.IsLoading then Library:SafeCall(kb.Callback, false) end
                        end
                    end)

                    if kb.Default then Keybind:Set({ Key = kb.Default, Mode = kb.Mode or "Toggle" }) end
                    return Keybind
                end

                return Label
            end

            -- ── Textbox ───────────────────────────────────
            function Section:Textbox(data4)
                data4 = data4 or {}
                local Textbox = {
                    Window  = Window,
                    Page    = Page,
                    Section = Section,
                    Name    = data4.Name or data4.name or "Textbox",
                    Flag    = data4.Flag or data4.flag or Library:NextFlag(),
                    Value   = "",
                }

                local column = getColumn(data4.Side or data4.side or 1)

                local Border = create("Frame", {
                    BackgroundColor3 = FromRGB(5, 5, 5),
                    BorderColor3     = FromRGB(30, 30, 30),
                    Size             = UDim2New(1, 0, 0, 30),
                }, column)

                local TB = create("TextBox", {
                    AnchorPoint          = Vector2New(0.5, 0.5),
                    BackgroundColor3     = FromRGB(25, 25, 25),
                    BorderColor3         = FromRGB(0, 0, 0),
                    Position             = UDim2New(0.5, 0, 0.5, 0),
                    Size                 = UDim2New(0, 215, 0, 20),
                    Font                 = Enum.Font.Ubuntu,
                    Text                 = data4.Default or data4.default or "",
                    TextColor3           = FromRGB(150, 150, 150),
                    TextSize             = 14,
                    PlaceholderText      = data4.Placeholder or data4.placeholder or "...",
                    ClearTextOnFocus     = false,
                }, Border)

                TB.MouseEnter:Connect(function()
                    Library:Tween(TB, TWEEN_FAST, { TextColor3 = FromRGB(255, 255, 255) })
                end)
                TB.MouseLeave:Connect(function()
                    Library:Tween(TB, TWEEN_FAST, { TextColor3 = FromRGB(150, 150, 150) })
                end)
                UserInputService.TextBoxFocused:Connect(function()
                    if UserInputService:GetFocusedTextBox() == TB then
                        Library:Tween(TB, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                            { BorderColor3 = FromRGB(84, 101, 255) })
                    end
                end)
                UserInputService.TextBoxFocusReleased:Connect(function()
                    Library:Tween(TB, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        { BorderColor3 = FromRGB(0, 0, 0) })
                end)
                TB:GetPropertyChangedSignal("Text"):Connect(function()
                    Textbox.Value              = TB.Text
                    Library.Flags[Textbox.Flag] = TB.Text
                    local cb = data4.Callback or data4.callback
                    if cb and not Library.IsLoading then Library:SafeCall(cb, TB.Text) end
                end)

                function Textbox:Set(v)
                    Textbox.Value              = tostring(v)
                    Library.Flags[Textbox.Flag] = Textbox.Value
                    TB.Text                    = Textbox.Value
                    local cb = data4.Callback or data4.callback
                    if cb and not Library.IsLoading then Library:SafeCall(cb, Textbox.Value) end
                end
                function Textbox:Get()             return Textbox.Value end
                function Textbox:SetVisibility(b)  Border.Visible = b    end

                Library.SetFlags[Textbox.Flag] = function(v) Textbox:Set(v) end

                return Textbox
            end

            -- expose Section metatable equivalents
            setmetatable(Section, Library.Sections)
            return Section
        end

        setmetatable(Page, Library.Pages)
        return Page
    end

    return Window
end

-- ============================================================
-- Config helpers  (Utopia-compatible)
-- ============================================================

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
        if type(v) == "table" and v.Key then fn(v)
        elseif type(v) == "table" and v.Color then fn(Color3.fromHex(v.Color))
        else fn(v) end
    end
end

-- Notification (lightweight)
function Library:Notification(text, duration, color, _icon)
    local Notif = create("Frame", {
        AnchorPoint      = Vector2New(0.5, 1),
        BackgroundColor3 = FromRGB(15, 15, 15),
        BorderColor3     = FromRGB(40, 40, 40),
        Position         = UDim2New(0.5, 0, 1, -10),
        Size             = UDim2New(0, 0, 0, 24),
        AutomaticSize    = Enum.AutomaticSize.X,
    }, Library.Holder)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Size           = UDim2New(0, 0, 1, 0),
        AutomaticSize  = Enum.AutomaticSize.X,
        Font           = Enum.Font.Ubuntu,
        Text           = text,
        TextColor3     = FromRGB(215, 215, 215),
        TextSize       = 13,
    }, Notif)

    create("UIPadding", {
        PaddingLeft  = UDimNew(0, 8),
        PaddingRight = UDimNew(0, 8),
    }, Notif)

    create("Frame", {
        BackgroundColor3 = color or FromRGB(84, 101, 255),
        BorderSizePixel  = 0,
        Size             = UDim2New(1, 0, 0, 2),
    }, Notif)

    task.delay(duration or 3, function()
        if Notif and Notif.Parent then Notif:Destroy() end
    end)
end

-- ============================================================
-- Finalise
-- ============================================================
Library.IsLoading = false

return Library
