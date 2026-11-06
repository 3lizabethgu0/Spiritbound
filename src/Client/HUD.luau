--!strict
-- In-night HUD: night number, phase, countdown, seal stars, guests, coins.
-- Built in code so it syncs through Rojo. Pure display: it never changes game state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)

type RunState = Types.RunState

local HUD = {}

local FONT = Enum.Font.GothamBold
local COLOR_TEXT = Color3.fromRGB(240, 236, 228)
local COLOR_DIM = Color3.fromRGB(170, 165, 155)
local COLOR_DAWN = Color3.fromRGB(255, 196, 92)
local COLOR_STAR = Color3.fromRGB(255, 221, 120)
local COLOR_STAR_LOST = Color3.fromRGB(70, 66, 60)
local COLOR_DANGER = Color3.fromRGB(255, 96, 96)
local COLOR_COIN = Color3.fromRGB(255, 200, 80)

local state: RunState? = nil

local nextOrder = 0
local function label(parent: Instance, name: string, size: number, color: Color3): TextLabel
	nextOrder += 1
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = nextOrder -- UIListLayout otherwise sorts by name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.6
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.Text = ""
	l.Parent = parent
	return l
end

-- Build once
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "SpiritboundHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local top = Instance.new("Frame")
top.Name = "Top"
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 16)
top.Size = UDim2.new(0, 320, 0, 138)
top.BackgroundColor3 = Color3.fromRGB(12, 10, 14)
top.BackgroundTransparency = 0.35
top.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = top
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder -- default sorts by Name
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 2)
layout.Parent = top
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = top

local nightLabel = label(top, "Night", 26, COLOR_TEXT)
local timerLabel = label(top, "Timer", 22, COLOR_DIM)

-- Seal stars: one cell per star. Each cell has a grey star underneath and a
-- gold star inside a clipping frame. Shrinking the clip's width cuts the gold
-- star off at the fraction, so 4.75 shows four gold stars and three quarters of a fifth.
local STAR_SIZE = 30
local starsRow = Instance.new("Frame")
starsRow.Name = "Stars"
starsRow.BackgroundTransparency = 1
starsRow.Size = UDim2.new(1, 0, 0, STAR_SIZE + 4)
nextOrder += 1
starsRow.LayoutOrder = nextOrder
starsRow.Parent = top
local starsLayout = Instance.new("UIListLayout")
starsLayout.FillDirection = Enum.FillDirection.Horizontal
starsLayout.SortOrder = Enum.SortOrder.LayoutOrder
starsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
starsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
starsLayout.Padding = UDim.new(0, 2)
starsLayout.Parent = starsRow

local function starGlyph(parent: Instance, color: Color3): TextLabel
	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.new(0, STAR_SIZE, 0, STAR_SIZE)
	glyph.Font = FONT
	glyph.TextSize = STAR_SIZE
	glyph.TextColor3 = color
	glyph.TextStrokeTransparency = 0.6
	glyph.Text = "★"
	glyph.Parent = parent
	return glyph
end

local starClips: { Frame } = {}
local function buildStars(maxStars: number)
	for _, child in starsRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(starClips)
	for i = 1, maxStars do
		local cell = Instance.new("Frame")
		cell.Name = ("Star%d"):format(i)
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.new(0, STAR_SIZE, 0, STAR_SIZE)
		cell.LayoutOrder = i
		cell.Parent = starsRow
		starGlyph(cell, COLOR_STAR_LOST)
		local clip = Instance.new("Frame")
		clip.Name = "Clip"
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Size = UDim2.new(1, 0, 1, 0)
		clip.Parent = cell
		starGlyph(clip, COLOR_STAR) -- full width inside the clip, so the clip's edge cuts it
		starClips[i] = clip
	end
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(0, 44, 0, STAR_SIZE)
	value.LayoutOrder = maxStars + 1
	value.Font = FONT
	value.TextSize = 14
	value.TextColor3 = COLOR_DIM
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = ""
	value.Parent = starsRow
end

local function setStars(stars: number, maxStars: number)
	if #starClips ~= maxStars then
		buildStars(maxStars)
	end
	for i, clip in starClips do
		local fill = math.clamp(stars - (i - 1), 0, 1)
		clip.Size = UDim2.new(fill, 0, 1, 0)
	end
	local value = starsRow:FindFirstChild("Value") :: TextLabel?
	if value then
		value.Text = ("%.2f"):format(stars)
	end
end

local guestsLabel = label(top, "Guests", 16, COLOR_DIM)

-- Coins sit in their own corner so the top block stays about the night
local coinsLabel = label(gui, "Coins", 24, COLOR_COIN)
coinsLabel.AnchorPoint = Vector2.new(1, 0)
coinsLabel.Position = UDim2.new(1, -24, 0, 24)
coinsLabel.Size = UDim2.new(0, 200, 0, 30)
coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
coinsLabel.Text = "0 coins"

local banner = Instance.new("TextLabel")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.42, 0)
banner.Size = UDim2.new(0, 600, 0, 120)
banner.BackgroundTransparency = 1
banner.Font = FONT
banner.TextSize = 40
banner.TextColor3 = COLOR_DANGER
banner.TextStrokeTransparency = 0.4
banner.TextWrapped = true
banner.Visible = false
banner.Parent = gui

gui.Parent = playerGui

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(s // 60, s % 60)
end


function HUD.setState(newState: RunState)
	state = newState
	setStars(newState.stars, newState.maxStars)

	if newState.phase == "Night" then
		nightLabel.Text = ("NIGHT %d"):format(newState.night)
		nightLabel.TextColor3 = COLOR_TEXT
		timerLabel.TextColor3 = COLOR_DIM
		guestsLabel.Text = ("guests served %d / %d"):format(newState.guestsServed, newState.guestsTotal)
		banner.Visible = false
	elseif newState.phase == "Dawn" then
		nightLabel.Text = "DAWN"
		nightLabel.TextColor3 = COLOR_DAWN
		timerLabel.TextColor3 = COLOR_DAWN
		guestsLabel.Text = ("last night: %d / %d served"):format(newState.guestsServed, newState.guestsTotal)
		banner.Visible = false
	else
		nightLabel.Text = "SEAL CRACKED"
		nightLabel.TextColor3 = COLOR_DANGER
		timerLabel.TextColor3 = COLOR_DIM
		guestsLabel.Text = ""
		banner.Text = ("The seal cracked.\nYou survived %d night%s."):format(newState.night, newState.night == 1 and "" or "s")
		banner.Visible = true
	end
end

-- Coins come from leaderstats, which the server owns and Roblox replicates
task.spawn(function()
	local stats = player:WaitForChild("leaderstats")
	local coins = stats:WaitForChild("Coins") :: IntValue
	local function refresh()
		coinsLabel.Text = ("%d coins"):format(coins.Value)
	end
	coins.Changed:Connect(refresh)
	refresh()
end)

-- Countdown runs locally from the server's absolute end time
RunService.RenderStepped:Connect(function()
	local s = state
	if not s then
		return
	end
	local remaining = s.phaseEndsAt - workspace:GetServerTimeNow()
	if s.phase == "Ended" then
		timerLabel.Text = ("next run in %s"):format(formatTime(remaining))
	else
		timerLabel.Text = formatTime(remaining)
	end
end)

return HUD
