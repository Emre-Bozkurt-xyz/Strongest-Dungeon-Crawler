--!strict
-- The System's notices, stacked at the top of the screen, oldest first.
--
-- Each switches on and off like a panel (components/SwitchOn). A notice that has left the store is
-- kept here, closing, until its close has finished; its slot shrinks with it, so the stack closes up
-- instead of jumping.
--
-- `script` here IS the Notifications module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local SwitchOn = require(script.Parent.Parent.components.SwitchOn)
local useNotifications = require(script.Parent.Parent.hooks.useNotifications)
local NotificationClient = require(script.Parent.Parent.controllers.NotificationClient)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local Notice = require(script.Notice)

local e = React.createElement

local CONFIG = SharedConfig.Notifications

type Entry = { notice: NotificationClient.Notice, leaving: boolean }

local function Notifications()
	local live = useNotifications()
	local shown, setShown = React.useState({} :: { Entry })

	-- Live notices update in place and new ones join the end; one that has gone from the store stays,
	-- marked leaving, until its close finishes.
	React.useEffect(function()
		setShown(function(previous: { Entry }): { Entry }
			local liveById: { [number]: NotificationClient.Notice } = {}
			for _, notice in ipairs(live) do
				liveById[notice.id] = notice
			end
			local nextShown: { Entry } = {}
			local present: { [number]: boolean } = {}
			for _, entry in ipairs(previous) do
				local current = liveById[entry.notice.id]
				table.insert(nextShown, { notice = current or entry.notice, leaving = current == nil })
				present[entry.notice.id] = true
			end
			for _, notice in ipairs(live) do
				if not present[notice.id] then
					table.insert(nextShown, { notice = notice, leaving = false })
				end
			end
			return nextShown
		end)
	end, { live })

	local function remove(id: number)
		setShown(function(previous: { Entry }): { Entry }
			local kept: { Entry } = {}
			for _, entry in ipairs(previous) do
				if entry.notice.id ~= id then
					table.insert(kept, entry)
				end
			end
			return kept
		end)
	end

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, CONFIG.gap),
		}),
	}
	for _, entry in ipairs(shown) do
		local id = entry.notice.id
		children[`Notice{id}`] = e(SwitchOn, {
			visible = not entry.leaving,
			size = Notice.SIZE,
			collapseSlot = true,
			layoutOrder = id,
			onClosed = function()
				remove(id)
			end,
		}, {
			View = e(Notice.render, { notice = entry.notice }),
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 1, -CONFIG.top),
		Position = UDim2.fromOffset(0, CONFIG.top),
		BackgroundTransparency = 1,
	}, children)
end

return Notifications
