print("[BPS] Loaded: sv_init.lua")

------------
-- Set-up --
------------

BPS.Players = BPS.Players or {}
BPS.SpriteTrails = {}

-- Set up cache (retrieve from SQL)
BPS.Stock = {
	Shop 	= BPS.RetrieveStock(),
	Market 	= BPS.RetrieveStock( true )
}

local netStrings = {
	"BPS_RequestData",
	"BPS_BuyItem",
	"BPS_BuyItemFromMarket",
	"BPS_BidOnItem",
	"BPS_UpdateBids",
	"BPS_SellItemOnMarket",
	"BPS_ReturnItemFromMarket",
	"BPS_ScrapItem",
	"BPS_EngraveItem",
	"BPS_RemoveEngrave",
	"BPS_RefreshStock",
	"BPS_RefreshPoints",
	"BPS_RefreshInventory",
	"BPS_AddToShop",
	"BPS_VerifyCustomiseItem",
	"BPS_ToggleEquip",
	"BPS_AddToDrawList",
	"BPS_RemoveFromDrawList",
	"BPS_ModifyFromDrawList",
	"BPS_ValidateDrawList",
	"BPS_RequestDrawList",
	"BPS_Notify",
	"BPS_RenameItem",
	"BPS_RecolourItem",
	"BPS_GiftPoints",
	"BPS_MM_AddToShop",
	"BPS_MM_RemoveFromShop",
	"BPS_MM_GivePoints",
	"BPS_MM_ResetPlayer",
	"BPS_KillUI",
	"BPS_NWTest"
}

local files = {
	"resource/fonts/SpaceMono-Regular.ttf",
	"resource/fonts/Cairo-Regular.ttf",
	"resource/fonts/Roboto-Medium.ttf",
	"resource/fonts/RobotoCondensed-Bold.ttf",
	"materials/bps/icon_tick.png",
	"materials/bps/icon_cross.png",
	"materials/bps/icon_inv.png",
	"materials/bps/icon_shop.png",
	"materials/bps/icon_market.png",
	"materials/bps/icon_manage.png",
	"materials/bps/icon_customise.png",
	"materials/bps/icon_equip.png",
	"materials/bps/icon_equipped.png",
	"materials/bps/icon_unequip.png",
	"materials/bps/icon_engrave.png",
	"materials/bps/icon_buy.png",
	"materials/bps/icon_lock.png",
	"materials/bps/icon_undo.png",
	"materials/bps/icon_hat.png",
	"materials/bps/icon_pmodel.png",
	"materials/bps/icon_trail.png",
	"materials/bps/icon_points.png",
	"materials/bps/icon_pointsVIP.png",
	"materials/bps/icon_timer.png",
	"materials/bps/icon_buysleft.png",
	"materials/bps/icon_error.png",
	"materials/bps/icon_delete.png",
	"materials/bps/icon_write.png",
	"materials/bps/icon_settings.png",
	"materials/bps/icon_newitem.png",
	"materials/bps/icon_gift.png",
	"materials/bps/icon_btnUp.png",
	"materials/bps/icon_btnDown.png",
	"materials/bps/icon_btnGrip.png",
	"materials/bps/icon_topbid.png",
	"sound/bps/click_001.ogg",
	"sound/bps/click_002.ogg",
	"sound/bps/click_003.ogg",
	"sound/bps/click_004.ogg",
	"sound/bps/click_005.ogg"
}

-- Set up network strings and clientside files (fonts, sounds, icons etc.)
for _, netString in pairs( netStrings ) do util.AddNetworkString( netString ) end
for _, file in pairs( files ) do resource.AddFile( file ) end

-- Set up access log directory
if !file.IsDir( "bps", "DATA" ) then file.CreateDir( "bps" ) end

-----------------------
-- Network functions --
-----------------------

-- Send a player's inventory + equipped list/ from cache
BPS.NW.SendInventory = function( p )
	
	net.Start( "BPS_RefreshInventory" )
	
	local inv = BPS.Players[p].Inv
	
	for _, category in pairs( {"Accessories","Playermodels","Trails"} ) do
		-- Write the number of items in this category
		net.WriteUInt( table.Count(inv[category]), 8 )
		
		-- Pack items
		for _, item in pairs( inv[category] ) do
			BPS.NW.PackItem( item, category )
		end
	end
	
	net.Send( p )
end

-- Send a player's points from cache
BPS.NW.SendPoints 	= function( p )
	
	net.Start( "BPS_RefreshPoints" )
	net.WriteUInt( BPS.Players[ p ].Points, 32 )
	net.WriteUInt( BPS.Players[ p ].PointsVIP, 32 )
	net.Send( p )
end

-- Send stock from cache
BPS.NW.SendStock 	= function( p, isMarket )
	
	net.Start		( "BPS_RefreshStock" )
	net.WriteBool	( isMarket )
	net.WriteTable	( BPS.Stock[ isMarket and "Market" or "Shop" ] )
	net.Send		( p or player.GetAll() )
end

-- Send an equip flag
BPS.NW.Equip 		= function( p, ID, category, doEquip )
	
	net.Start("BPS_ToggleEquip")
	net.WriteUInt( ID, 24 )
	net.WriteBool( doEquip )
	net.WriteString( category )
	net.Send( p )
end

-- Broadcast bidding update on a market item
BPS.NW.UpdateBids 	= function( ID, bids )

	net.Start( "BPS_UpdateBids" )
	net.WriteUInt( ID, 24 )
	net.WriteUInt( #bids, 3 )
	for _, bid in ipairs(bids) do
		net.WriteUInt( bid, 24 )
	end
	net.Broadcast()
end 

-- Broadcast item draw data to add to client draw list. Omit player to broadcast
BPS.AddToDrawList	= function( p, ID, item, pTarget )
	
	net.Start		( "BPS_AddToDrawList" )
	net.WriteEntity	( p )
	net.WriteUInt	( ID, 32 )
	net.WriteTable 	( item )
	net.Send 		( pTarget or player.GetAll() )
end

-- Broadcast update to remove item(s) from clientside draw list
BPS.RemoveFromDrawList = function( p, ID )
	
	net.Start		( "BPS_RemoveFromDrawList" )
	net.WriteString	( p:SteamID() )
	net.WriteInt	( ID, 32 ) -- Pass -1 to delete all the player's draw items
	net.Broadcast	()
end

-- Broadcast update to modify an item from clientside draw list
BPS.ModifyFromDrawList = function( p, ID, item )
	
	net.Start		( "BPS_ModifyFromDrawList" )
	net.WriteString	( p:SteamID() )
	net.WriteUInt 	( ID, 32 )
	net.WriteTable 	( item )
	net.Broadcast()
end

-- Force clients to validate drawlist (remove disconnected players)
BPS.ValidateDrawList = function()

	net.Start( "BPS_ValidateDrawList" )
	net.Broadcast()
end

-- Create notification on player screen
BPS.NW.Notify 		= function( p, message, icon, duration )
	
	net.Start		( "BPS_Notify" )
	net.WriteString	( message )
	net.WriteString	( icon )
	net.WriteUInt	( duration, 4 )
	net.Send		( p )
end

-- Kill UI
BPS.KillUI 			= function( p )
	
	net.Start( "BPS_KillUI" )
	net.Send( p )
end

---------------
-- Mid-layer --
---------------

BPS.DoEquip 	= function( p, ID, item, category, doEquip )
	
	-- Category disabled, stop here
	if (!BPS.CONF.EnablePlayermodels and category == "Playermodels") or (!BPS.CONF.EnableTrails and category == "Trails") then return end
	
	-- No change needed
	if (BPS.GetEquipped( p, ID ) ~= nil) == doEquip then return end
	
	-- Set flag and network
	BPS.SetEquipped( p, ID, category, doEquip )
	BPS.NW.Equip( p, ID, category, doEquip )
	
	-- Player not alive, stop here
	if !p:Alive() then return end
	
	-- Equip
	if category == "Accessories" then
		
		if doEquip then	
			BPS.AddToDrawList( p, ID, item )
		else
			BPS.RemoveFromDrawList( p, ID )
		end
	elseif category == "Playermodels" then
		
		BPS.SetPModel( p, doEquip and item or nil )
	elseif category == "Trails" then
		
		if doEquip then
			BPS.MakeTrail( p, item )
		else
			BPS.KillTrail( p )
		end
	end
end


BPS.SetPModel 	= function( p, pmodel )
	
	if pmodel then
		
		p._prevPModel 	= { -- Equipping. Cache current pmodel
			Model 		= p:GetModel(),
			Skin 		= p:GetSkin(),
			Colour 		= p:GetPlayerColor()
		}
		
		-- Convert RGB
		pmodel.Colour = Vector(pmodel.Colour.r/255, pmodel.Colour.g/255, pmodel.Colour.b/255)
	else
		
		pmodel = p._prevPModel		-- Load cached pmodel for unequip
		if !pmodel then return end	-- No cache
	end
	
	p:SetModel			( pmodel.Model )
	p:SetSkin			( pmodel.Skin )
	p:SetPlayerColor 	( pmodel.Colour )
end

BPS.MakeTrail 	= function( p, trail )
	
	BPS.KillTrail( p )
	BPS.SpriteTrails[p] = util.SpriteTrail( p, 0, trail.Colour, false, 32, 0, 3, 1/8, trail.Trail )
end

BPS.KillTrail 	= function( p )
	
	if IsValid(BPS.SpriteTrails[p]) then BPS.SpriteTrails[p]:Remove() end
end

-- Count owned items
BPS.GetInvCount = function( p )
	
	local inv 	= BPS.GetInventory( p )
	local pSID 	= p:SteamID()
	local N 	= 0
	
	for _, items in pairs( inv ) do -- Count inventory items
		N = N + table.Count(items)
	end
	
	for _, items in pairs( BPS.RetrieveStock(true) ) do -- Count owned market items
		for _, item in pairs( items ) do
			if item.SID == pSID then N = N + 1 end
		end
	end
	
	return N
end

------------------
-- Transactions --
------------------

-- Perform a market transaction + network
local PerformMarketTransaction = function( buyer, seller, item, price )
	
	-- Check if players are online
	if type(buyer) == "string" then buyer = player.GetBySteamID(buyer) or buyer end
	if type(seller) == "string" then seller = player.GetBySteamID(seller) or seller end
	
	local buyerOnline, sellerOnline	= type(buyer) == "Player", type(seller) == "Player"
	
	-- Notify
	if buyerOnline then BPS.NW.Notify( buyer, ("You've bought %s from %s for %i %ss!"):format(item.Name, item.Shop.Nick, price, BPS.CONF.PointName), "Buy", 5 ) end
	if sellerOnline then BPS.NW.Notify( seller, ("%s bought your Market item for +%i %ss!"):format(buyer:Nick(), price, BPS.CONF.PointName), "Buy", 10 ) end
	
	BPS.RemoveFromMarket( item.ID, false ) 	-- Take item off the market
	BPS.GivePoints( buyer, -price ) 		-- Deduct points from buyer
	BPS.GivePoints( seller, price ) 		-- Give points to seller
	item.Shop = nil 						-- Remove shop info
	BPS.GiveItem( buyer, item ) 			-- Give buyer the item
	
	-- Network
	BPS.NW.SendStock( nil, true )
	if buyerOnline then 
		BPS.NW.SendInventory( buyer )
		BPS.NW.SendPoints( buyer )
	end
	if sellerOnline then 
		BPS.NW.SendInventory( seller ) 
		BPS.NW.SendPoints( seller )
	end
end

---------------------
-- Client requests --
---------------------

-- Client request for data
net.Receive( "BPS_RequestData", function( l, p )

	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Player requested their own data
	if net.ReadBool() then
		-- Send inv, points
		BPS.NW.SendInventory( p )
		BPS.NW.SendPoints( p )
		
		-- Send equip list
		for ID, category in pairs( BPS.GetEquipped(p) ) do BPS.NW.Equip( p, ID, category, true ) end
	end
	
	-- Player requested stock data
	if net.ReadBool() then
		-- Send stock data
		BPS.NW.SendStock( p )
		BPS.NW.SendStock( p, true )
	end
end )

-- Client asks to buy a shop item
net.Receive( "BPS_BuyItem", function( l, p )
	
	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Read shop UID
	local ID = net.ReadUInt( 32 )
	
	-- Retrieve matching shop item
	local item, category, idx = BPS.RetrieveItem( ID )
	
	-- Lookup failed
	if !item then return end
	
	-- Category disabled
	if (!BPS.CONF.EnablePlayermodels and category == "Playermodels") or (!BPS.CONF.EnableTrails and category == "Trails") then return end
	
	-- Inventory is full
	if BPS.GetInvCount( p ) >= BPS.CONF.InventoryLimit then
		BPS.NW.Notify( p, "Sorry, your inventory is full!", "Error", 3 )
	return end
	
	-- Verify player has enough points
	if BPS.GetPoints( p, item.Shop.VIP ) < item.Shop.Cost then 
		BPS.NW.Notify( p, "You don't have enough " .. BPS.CONF.PointName .. "s!", "Error", 3 )
	return end
	
	-- Limited stock items
	local buysLeft = item.Shop.BuysLeft
	if buysLeft then
		if buysLeft > 1 then
			-- Deduct from stock
			item.Shop.BuysLeft = buysLeft - 1
			BPS.ModifyShopItem( ID, {Shop = item.Shop} )
		else
			-- Out of stock; delete
			BPS.RemoveFromShop( ID, category, idx )
		end
		
		BPS.NW.SendStock()
	end
	
	-- Perform transaction
	p:BPS_GivePoints( -item.Shop.Cost, item.Shop.VIP, false ) -- Deduct points
	item.Shop = nil
	BPS.GiveItem( p, item ) -- Give buyer the item
	
	-- Let the player know
	BPS.NW.SendInventory( p )
	BPS.NW.Notify( p, "You've bought " .. item.Name .. "!", "Buy", 3 )
end )

-- Client asks to buy a market item
net.Receive( "BPS_BuyItemFromMarket", function( l, p )
	
	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Retrieve item from cache
	local ID = net.ReadUInt( 32 )
	local item, category = BPS.RetrieveItem( ID, true )
	
	-- Verify item exists
	if !item then return end
	
	-- Verify inv isn't full
	if BPS.GetInvCount( p ) >= BPS.CONF.InventoryLimit then
		BPS.NW.Notify( p, "Sorry, your inventory is full!", "Error", 3 )
	return end
	
	-- Verify player has enough points
	if BPS.GetPoints( p ) < item.Shop.Cost then 
		BPS.NW.Notify( p, "You don't have enough " .. BPS.CONF.PointName .. "s!", "Error", 3 )
	return end
	
	-- Do transaction
	PerformMarketTransaction( p, item.Shop.SID, item, item.Shop.Cost )
end )

-- Client asks to bid on a market item
net.Receive( "BPS_BidOnItem", function( l, p )

	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Read identifier and retrieve item/category data from market database
	local ID = net.ReadUInt( 24 )
	local bid = net.ReadUInt( 24 )
	local item, category, idx = BPS.RetrieveItem( ID, true )
	
	-- No data
	if !item or !bid then return end
	
	-- Verify inv isn't full
	if BPS.GetInvCount( p ) >= BPS.CONF.InventoryLimit then
		BPS.NW.Notify( p, "Sorry, your inventory is full!", "Error", 3 )
	return end
	
	-- Verify bid is sufficient
	local bidMin = item.Shop.Bids[1] + BPS.CONF.MinBidIncrement
	if bid < bidMin then
		BPS.NW.Notify( p, "The minimum bid for this item is " .. string.Comma(bidMin) .. " " .. BPS.CONF.PointName .. "s!", "Error", 3 )
	return end
	
	-- Verify player has enough points
	if BPS.GetPoints( p ) < bid then 
		BPS.NW.Notify( p, "You don't have enough " .. BPS.CONF.PointName .. "s!", "Error", 3 )
	return end
	
	-- Retrieve bidding update from MySQL
	if BPS.CONF.UseMySQL then
		
		--
		
	end
	
	-- Checks passed; update the bid
	local newBids = BPS.PlaceBid( p, ID, category, idx, bid )
	
	-- Network changes (from cache)
	BPS.NW.UpdateBids( ID, newBids )
	BPS.NW.Notify( p, "Your bid on " .. item.Name .. " has been placed!", "Bid", 3 )
end )

-- Client asks to withdraw a market item
net.Receive( "BPS_ReturnItemFromMarket", function( l, p )
	
	if !BPS.CONF.MarketAllowWithdraw then return end
	
	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Read identifier and retrieve item data from market database
	local ID = net.ReadInt( 32 )
	local item, category = BPS.RetrieveItem( ID, true )
	
	-- Verify (1) the item exists and (2) this player owns it
	if !item or p:SteamID() != item.Shop.SID then return end
	
	-- Withdraw the item
	BPS.RemoveFromMarket( ID )
	
	-- Network
	BPS.NW.SendInventory( p )
	BPS.NW.SendStock( nil, true )
	BPS.NW.Notify( p, ("%s was withdrawn from the market."):format(item.Name), "Withdraw", 3 )
end )

-- Client asks to put an item up for sale via the market
net.Receive( "BPS_SellItemOnMarket", function( l, p )
	
	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Verify the market isn't saturated
	local canSell, marketFull = BPS.CanAddToMarket(p)
	
	if !canSell then 
		if marketFull then
			BPS.NW.Notify( p, "Sorry, the market is full right now! Try again later.", "Cross", 5 )
		else
			BPS.NW.Notify( p, "Sorry, you can only have " .. BPS.CONF.MarketLimitPlayer .. " items for sale at once!", "Tick", 5 )
		end
	return end
	
	-- Read the item ID and chosen sale price
	local ID = net.ReadInt(32)
	local price = net.ReadInt(32)
	
	-- Verify data present
	if !ID or !price then return end
	
	-- Clamp price to within limits
	price = math.Clamp(price, 1, BPS.CONF.MaxMarketPrice)
		
	-- Retrieve and remove the item
	local item, category = BPS.RemoveItem( p, ID )
	
	-- Lookup failed
	if !item then return end
	
	-- Checks passed
	BPS.DoEquip( p, ID, item, category, false ) -- Unequip
	BPS.AddToMarket( p, item, category, price ) -- Add the item to market
	BPS.NW.SendInventory( p ) -- Network changes
	BPS.NW.SendStock( nil, true )
	
	-- Notify
	BPS.NW.Notify( p, ("Your item is now for sale!"):format(item.Name, item.Nick), "Tick", 5 )
end )

-- Client asks to scrap an item
net.Receive( "BPS_ScrapItem", function( l, p )
	
	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Read item ID and retrieve the item
	local ID = net.ReadUInt(32)
	local item, category = BPS.RetrievePlayerItem( p, ID )
	
	-- Lookup failed, abort
	if !item then return end
	
	-- Unequip and remove the item. Update inv
	BPS.DoEquip( p, ID, item, category, false )
	BPS.RemoveItem( p, ID )
	BPS.NW.SendInventory( p )
	BPS.NW.Notify( p, "Scrapped " .. item.Name, "Delete", 5 )
end )

-- Client asks to customise an accessory
net.Receive( "BPS_VerifyCustomiseItem", function( l, p )
	
	-- Verify player valid and customisation is enabled
	if not ( IsValid(p) and p:IsPlayer() and BPS.CONF.EnableCustomise ) then return end
	
	-- Receive item data
	local ID 		= net.ReadUInt( 32 )
	local modData 	= net.ReadTable()
	local invItem 	= BPS.RetrievePlayerItem( p, ID )
	
	-- Lookup failed, abort
	if !invItem then return end
	
	-- Error prevention in case client tries to send modData with voids/invalid data types (note invItem is already devoided on retrieval)
	for k, v in pairs( invItem ) do
		if modData[k] == nil or type(modData[k]) ~= type(v) then 
			modData[k] = v
		end
	end
	
	-- Clamp data
	invItem.Offset.x 	= math.Clamp( modData.Offset.x, -BPS.CONF.MaxOffset, BPS.CONF.MaxOffset )
	invItem.Offset.y 	= math.Clamp( modData.Offset.y, -BPS.CONF.MaxOffset, BPS.CONF.MaxOffset )
	invItem.Offset.z 	= math.Clamp( modData.Offset.z, -BPS.CONF.MaxOffset, BPS.CONF.MaxOffset )
	
	if BPS.CONF.EnableScale then
		invItem.Scale 	= math.Clamp( modData.Scale, -BPS.CONF.MaxScale, BPS.CONF.MaxScale )
	end
	
	-- Normalize angle
	invItem.Rotate = Angle( modData.Rotate.p % 360, modData.Rotate.y % 360, modData.Rotate.r % 360 )
	
	if BPS.CONF.EnableRecolor 	then invItem.Colour = modData.Colour end
	if BPS.CONF.EnableSwapBone 	then invItem.Bone = modData.Bone end
	
	-- Check bone valid
	if !table.KeyFromValue( BPS.CONF.Bones, invItem.Bone ) then
		invItem.Bone = BPS.CONF.Bones[1]
	end
	
	-- Write changes
	BPS.ModifyItem( p, ID, invItem )
	
	-- If player is alive and the item equipped (i.e. it is on the CS draw list), broadcast changes
	if p:Alive() and BPS.GetEquipped( p, ID ) then BPS.ModifyFromDrawList( p, ID, invItem ) end
end )

-- Client asks to engrave an item
net.Receive( "BPS_EngraveItem", function( l, p )
	
	-- Verify player valid and engraving is enabled
	if not ( IsValid(p) and p:IsPlayer() and BPS.CONF.EnableEngrave ) then return end
	
	-- Read item ID and engrave data
	local ID 	= net.ReadInt( 32 )
	local text 	= net.ReadString()
	local item 	= BPS.RetrievePlayerItem( p, ID )
	
	-- Verify overwrite allowed
	if item.Engrave and !BPS.CONF.EnableReEngrave then return end
	
	-- Lookup failed or text missing/invalid, abort
	if !item or !text or text == "" or #text > 100 then return end
	
	-- Verify content
	if BPS.CONF.EnableContentFilter then
		for word in pairs( BPS.Censors ) do
			if string.find( text:lower(), word:lower() ) then 
				BPS.NW.Notify( p, "Sorry, that engraving isn't allowed! Try another one.", "Error", 3 )
			return end
		end
	end
	
	-- Modify the item
	BPS.ModifyItem( p, ID, {Engrave = ("%q"):format(text), EngraveNick = ("- %s"):format(p:Nick())} )
	
	-- Network
	BPS.NW.SendInventory( p )
end )

-- Client asks to remove engraving
net.Receive( "BPS_RemoveEngrave", function( l, p )

	-- Verify player valid and action is allowed
	if not ( IsValid(p) and p:IsPlayer() and BPS.CONF.EnableReEngrave ) then return end
	
	-- Read item ID
	local ID = net.ReadUInt( 32 )
	
	-- Remove engraving
	BPS.ModifyItem( p, ID, {Engrave = 0}, true )
end )

-- Client asks to rename an item
net.Receive( "BPS_RenameItem", function( l, p )
	
	-- Verify player valid and engraving is enabled
	if not( IsValid(p) and p:IsPlayer() and BPS.CONF.EnableRename ) then return end
	
	-- Read item ID and new name
	local ID 	= net.ReadInt( 32 )
	local name 	= net.ReadString()
	
	-- Verify within character limit
	if !name or name == "" or #name > 16 then return end
	
	-- Verify content
	if BPS.CONF.EnableContentFilter then
		for word in pairs( BPS.Censors ) do
			if string.find( name:lower(), word:lower() ) then 
				BPS.NW.Notify( p, "Sorry, that name isn't allowed! Try another one.", "Error", 3 )
			return end
		end
	end
	
	-- Change the name and let the player know. Silent fails if ID is invalid
	BPS.ModifyItem		( p, ID, {Name = name} )
	BPS.NW.SendInventory( p )
	BPS.NW.Notify 			( p, "Rename successful!", "Rename", 3 )
end )

-- Client asks to recolour a pmodel/trail
net.Receive( "BPS_RecolourItem", function( l, p )
	
	-- Verify player valid and recolour is enabled
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Read item ID and new colour
	local ID 		= net.ReadUInt( 32 )
	local colour 	= net.ReadColor()
	
	local item, category = BPS.RetrievePlayerItem( p, ID )
	
	-- Recol disabled, stop here
	if category == "Playermodels" and !BPS.CONF.EnablePModelRecolor then return end
	
	colour.a = 255 -- Clamp transparency
	
	BPS.ModifyItem( p, ID, {Colour = colour} )
	
	-- If equipped, recolour now
	if BPS.GetEquipped( p, ID ) then
		
		if category == "Playermodels" then
			
			p:SetPlayerColor(Vector(colour.r/255, colour.g/255, colour.b/255))
		elseif category == "Trails" then
			
			BPS.MakeTrail( p, item )
		end
	end
end )

-- Client asks to gift points to another player
net.Receive( "BPS_GiftPoints", function( l, p )
	
	-- Verify player valid
	if !IsValid(p) then return end
	
	local player 	= player.GetBySteamID( net.ReadString() )
	local amount 	= net.ReadUInt(32)
	local doVIP 	= net.ReadBool()
	
	-- Verify target player is valid
	if !IsValid(player) or p == player or p:SteamID() == player:SteamID() or amount == 0 then return end
	
	-- Verify sender has enough points
	if BPS.GetPoints( p, doVIP ) < amount then
		BPS.NW.Notify( p, "You don't have enough " .. BPS.CONF.PointName .. "s!", "Error", 3 )
	return end
	
	-- Do the transaction
	p:BPS_GivePoints 		( -amount, doVIP, false )
	player:BPS_GivePoints	( amount, doVIP, true )
	
	-- Notify sender
	BPS.NW.Notify( p, "Points sent!", "Tick", 3 )
end )

-- Client asks to (un)equip an item
net.Receive( "BPS_ToggleEquip", function( l, p )
	
	-- Verify player valid
	if not ( IsValid(p) and p:IsPlayer() ) then return end
	
	-- Read item ID and retrieve item
	local ID = net.ReadUInt(24)
	local item, category = BPS.RetrievePlayerItem( p, ID )
	local doEquip = !BPS.GetEquipped( p, ID ) -- Determine whether we equip or unequip
	
	-- Lookup failed, abort
	if !item then return end
	
	-- Equip checks
	if doEquip then
		
		if category == "Accessories" and BPS.CountEquipped( p ) >= BPS.CONF.EquipLimit then
			
			BPS.NW.Notify( p, "Sorry, you can't equip any more Accessories!", "Error", 3 )
			return
		elseif category == "Playermodels" or category == "Trails" then
			
			-- Look for an equipped item
			local equippedID = next( BPS.GetEquipped( p )[category] )
			
			-- If there's already one equipped, swap it out
			if equippedID then
				
				-- Fetch the item and unequip
				local equippedItem = BPS.RetrievePlayerItem( p, equippedID )
				BPS.DoEquip( p, equippedID, equippedItem, category, false )
			end
		end
	end
	
	-- (Un)equip
	BPS.DoEquip( p, ID, item, category, doEquip )
	
	-- Notify
	if doEquip then
		BPS.NW.Notify( p, "Equipped " .. item.Name, "Equip", 3 )
	else
		BPS.NW.Notify( p, "Unequipped " .. item.Name, "Unequip", 3 )
	end
end )

-----------------
-- Manage mode --
-----------------

-- <MM> Delete shop/market item
net.Receive( "BPS_MM_RemoveFromShop", function( l, p )

	-- Verify player valid
	if !IsValid(p) or !p:IsPlayer() or !BPS.IsAdmin(p) then return end
	
	-- Read item ID and where to delete from
	local ID 		= net.ReadUInt( 32 )
	local isMarket 	= net.ReadBool()
	
	-- Retrieve item
	local item, category, idx = BPS.RetrieveItem( ID, isMarket )
	
	-- Remove the item
	if isMarket then
		BPS.RemoveFromMarket( ID )
	else
		BPS.RemoveFromShop( ID, category, idx )
	end
	
	-- Log
	file.Append( "bps/bps_log.txt", ("[%s] %s (%s) deleted item %q from the %s\n"):format( os.date("%c"), p:Nick(), p:SteamID(), item.Name, isMarket and "Market" or "Shop" ) )
	
	BPS.NW.SendStock( player.GetAll(), isMarket, ID )
end )

-- <MM> Create or modify shop item
net.Receive( "BPS_MM_AddToShop", function( l, p )
	
	-- Verify player valid
	if !IsValid(p) or !p:IsPlayer() or !BPS.IsAdmin(p) then return end
	
	-- Read data
	local item = net.ReadTable()
	
	-- Nullify zeroes
	if item.Shop.Expiry == 0 then item.Shop.Expiry = nil end
	if item.Shop.BuysLeft == 0 then item.Shop.BuysLeft = nil end
	
	if item.ID == 0 then
		
		-- Create new shop item
		BPS.AddToShop( item.Category, item )
		BPS.NW.Notify( p, "Done! Players can now buy this item.", "Manage", 5 )
		BPS.NW.SendStock()
		
		-- Log
		file.Append( "bps/bps_log.txt", ("[%s] %s (%s) added item %q to the Shop\n"):format( os.date("%c"), p:Nick(), p:SteamID(), item.Name ) )
	else
		
		-- Update shop item + broadcast changes to trigger UI refresh
		BPS.ModifyShopItem( item.ID, item )
		BPS.NW.Notify( p, "Changes saved!", "Manage", 3 )
		BPS.NW.SendStock()
		
		-- Log
		file.Append( "bps/bps_log.txt", ("[%s] %s (%s) modified the Shop item: %q\n"):format( os.date("%c"), p:Nick(), p:SteamID(), item.Name ) )
	end
end )

-- <MM> Give points
net.Receive( "BPS_MM_GivePoints", function( l, p )
	
	-- Verify player valid
	if !IsValid(p) or !p:IsPlayer() or !BPS.IsAdmin(p) then return end
	
	local player 	= player.GetBySteamID( net.ReadString() )
	local amount 	= net.ReadInt(32)
	local doVIP 	= net.ReadBool()
	
	-- Verify target player is valid
	if !IsValid(player) or !player:IsPlayer() then return end
	
	player:BPS_GivePoints( amount, doVIP, true )
	
	-- Log
	file.Append( "bps/bps_log.txt", ("[%s] %s (%s) gave %i %ss to player: %s\n"):format( os.date("%c"), p:Nick(), p:SteamID(), amount, doVIP and BPS.CONF.PointVIPName or BPS.CONF.PointName, player:Nick() ) )
end )

-- <MM> Reset player
net.Receive( "BPS_MM_ResetPlayer", function( l, p )
	
	-- Verify player valid
	if !IsValid(p) or !p:IsPlayer() or !BPS.IsAdmin(p) then return end
	
	local player = player.GetBySteamID( net.ReadString() )
	
	-- Verify target player is valid
	if !IsValid(player) or !player:IsPlayer() then return end
	
	player:BPS_Reset()
	BPS.NW.Notify( p, "Reset " .. player:Nick(), "Tick", 5 )
	
	-- Log
	file.Append( "bps/bps_log.txt", ("[%s] %s (%s) applied a full reset to player: %s\n"):format( os.date("%c"), p:Nick(), p:SteamID(), player:Nick() ) )
end )

-- New-join drawlist request
net.Receive( "BPS_RequestDrawList", function( l, pJoin )
	
	if !IsValid(pJoin) or !pJoin:IsPlayer() then return end
	
	-- Reconstruct and send draw list
	for i, p in pairs( player.GetAll() ) do
		
		local inv = BPS.GetInventory( p )
		
		for ID, category in pairs( BPS.GetEquipped( p ) ) do
			if category == "Accessories" then
				BPS.AddToDrawList( p, ID, inv.Accessories[ID], pJoin )
			end
		end
	end
end )

-----------
-- Hooks --
-----------

-- Register new-joins and cache data
hook.Add( "PlayerInitialSpawn", "BPS_PlayerJoin", function( p ) 
	
	local inv, points, pointsVIP, equip = BPS.Register( p ) -- Register player with SQL and retrieve data
	
	-- Cache
	BPS.Players[p] = {
		Inv 		= inv,
		Points		= points,
		PointsVIP	= pointsVIP,
		Equipped 	= equip,
		LastReward 	= os.time() -- Log join time for rewards tracking
	}
end )

-- <!!> TEMP
-- hook.Run( "PlayerInitialSpawn", player.GetAll()[1] )

-- Player spawn (equip: Accessories + Trails)
hook.Add( "PlayerSpawn", "BPS_PlayerSpawn", function( p )
	
	-- Retreive equipped list and inventory
	local equip = BPS.GetEquipped( p )
	local inv = BPS.GetInventory( p )
	
	-- Perform equips
	for ID, _ in pairs( equip ) do
		
		-- Add accessory to draw list
		local item = inv.Accessories[ID]
		if item then BPS.AddToDrawList( p, ID, item ) end
		
		-- Create trail
		local item = inv.Trails[ID]
		if item then BPS.MakeTrail( p, item ) end
	end
end )

-- Player spawn (equip: Playermodels)
hook.Add( "PlayerSetModel", "BPS_PlayerSpawn_PModel", function( p )

	-- Retrieve equipped playermodel
	local pmodel
	for ID, category in pairs( BPS.GetEquipped( p ) ) do
		if category == "Playermodels" then
			pmodel = BPS.RetrievePlayerItem( p, ID )
		break end
	end
	
	-- None found
	if !pmodel then return end
	
	-- Set playermodel next frame to override GM
	timer.Simple( 0, function() BPS.SetPModel( p, pmodel ) end )
end )

-- Player death (unequip all)
hook.Add( "PlayerDeath", "BPS_PlayerDeath", function( p )
	
	BPS.RemoveFromDrawList( p, -1 ) -- Stop drawing this player's items
	BPS.KillTrail( p ) 				-- Sprite persists after player death, so we call this to avoid stacking
end )

-- Player disconnect (unequip all)
hook.Add( "PlayerDisconnected", "BPS_PlayerDisconnect", function( p )
	
	-- Garbage collect entities
	BPS.ValidateDrawList()
end )

----------
-- Misc --
----------

-- Set-up content filtering
do
	BPS.Censors = {}

	local f = file.Open( "cfg/censor.txt", "r", "GAME" )

	-- Populate content filter list. Remove line breaks
	while not f:EndOfFile() do
		
		BPS.Censors[ string.gsub( f:ReadLine(), "\n", "" ) ] = true 
	end
	f:Close()
end

------------
-- Timers --
------------

if BPS.CONF.UseMySQL then
	-- Sync with MySQL; close bid requests; and remove expired items. Must loop over expired items (while)
	timer.Create( "BPS_MySQLRefresh", BPS.CONF.MySQLRefreshRate, 0, function()
		
		-- Retrieve from SQL
		BPS.Stock.Shop = BPS.RetrieveStock()
		BPS.Stock.Market = BPS.RetrieveStock( true )
		
		-- Network cache
		BPS.NW.SendStock()
		BPS.NW.SendStock( nil, true )
	end )
else
	-- Close bids and remove expired items
	timer.Create( "BPS_ExpiryChecker", 5, 0, function()
		
		local expShopItem = BPS.FindExpiredItem()
		local expMarketItem = BPS.FindExpiredItem( true )
		
		if expShopItem then
			
			--
			
		end
		
		if expMarketItem then
			
			local bids = expMarketItem.Shop.Bids
			
			if !bids or bids[1] == 0 then
				-- No buyers. Withdraw the item
				BPS.RemoveFromMarket( expMarketItem.ID )
				
				-- Network
				local seller = player.GetBySteamID(expMarketItem.Shop.SID)
				if seller then 
					BPS.NW.SendInventory( seller ) 
					BPS.NW.Notify( seller, ("%s was withdrawn from the market."):format(expMarketItem.Name), "Withdraw", 5 )
				end
				BPS.NW.SendStock( nil, true )
			else
				-- Close bid + network
				PerformMarketTransaction( expMarketItem.Shop.BidSID, expMarketItem.Shop.SID, expMarketItem, bids[1] )
			end
		end
	end )
end

-- Award points for playtime + cache garbage collection
timer.Create( "BPS_AwardPoints", 5, 0, function()
	
	for p, data in pairs( BPS.Players ) do
		
		if IsValid(p) then
			
			local timeNow = os.time()
			local timeSinceAward = timeNow - data.LastReward
			
			if timeSinceAward > BPS.CONF.RewardFrequency then
				
				p:BPS_GivePoints( BPS.CONF.RewardAmount, false, true, ("You've received +%i %ss for playing!"):format(BPS.CONF.RewardAmount, BPS.CONF.PointName) )
				
				data.LastReward	= timeNow -- Reset counter
			end
		else
			-- Garbage collection
			BPS.Players[p] = nil
		end
	end
end )
