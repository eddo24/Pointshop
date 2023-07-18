print("[BPS] Loaded: sv_data.lua")

-- Set up databases
if !sql.TableExists( "BPS_Shop" ) then sql.Query( "CREATE TABLE BPS_Shop ( ID INTEGER NOT NULL, Item TEXT, Category TEXT, Cost INTEGER, VIP BIT(1), Expiry INTEGER, BuysLeft INTEGER, PRIMARY KEY (ID AUTOINCREMENT) )" ) end
if !sql.TableExists( "BPS_Market" ) then sql.Query( "CREATE TABLE BPS_Market ( ID INTEGER NOT NULL, SID TEXT, Nick TEXT, Item TEXT, Category TEXT, Cost INTEGER, SaleTime INTEGER, Bids STRING, BidSID TEXT, PRIMARY KEY (ID AUTOINCREMENT) )" ) end
if !sql.TableExists( "BPS_Player" ) then sql.Query( "CREATE TABLE BPS_Player ( SID TEXT, Inv TEXT, Equip TEXT, Points INTEGER, PointsVIP INTEGER, LastJoin INTEGER )" ) end

-- On start-up, check for expired players
sql.Query( "DELETE FROM BPS_Player WHERE LastJoin <= " .. os.time() - BPS.CONF.PlayerExpiryTime * 86400 )

---------------------
-- Cache retrieval --
---------------------

-- Retrieve an item from stock cache by ID
BPS.RetrieveItem = function( ID, isMarket )
	for category, stock in pairs(BPS.Stock[isMarket and "Market" or "Shop"]) do
		for i, item in pairs(stock) do
			-- Return a deep copy
			if item.ID == ID then return table.Copy(item), category, i end
		end
	end
end

-- Retrieve an item from inventory cache by ID
BPS.RetrievePlayerItem = function( p, ID )
	
	local inv = BPS.Players[p].Inv
	
	if !inv then return end -- Lookup failed
	
	for category, items in pairs(inv) do
		-- Attempt to index to item
		local item = items[ID]
		
		if item then
			-- Item found
			BPS.CleanItem( item, category )
			return item, category
		end
	end
end

---------------------
-- Player database --
---------------------

-- Register and retrieve data
BPS.Register 		= function( p )
	
	local SID = IsValid(p) and p:SteamID() or p
	
	if !SID then return end
	
	local inv, points, pointsVIP, equip
	
	-- Existing player or new player?
	if sql.Query(( "SELECT SID FROM BPS_Player WHERE SID = %q" ):format( SID )) ~= nil then
		-- Retrieve data from SQL
		inv = BPS.GetInventory( p, true )
		points = BPS.GetPoints( p, true )
		pointsVIP = BPS.GetPoints( p, true )
		equip = BPS.GetEquipped( p, nil, true )
		
		-- Update LastJoin
		sql.Query( ( "UPDATE BPS_Player SET LastJoin = %i WHERE SID = %q" ):format( os.time(), SID ) )
	else
		-- New player
		points, pointsVIP, equip, inv = 0, 0, {}, {
			Accessories = {},
			Playermodels = {},
			Trails = {}
		}
		
		sql.Query( ( "INSERT INTO BPS_Player VALUES ( %q, '%s', '%s', %i, 0, %i )" ):format( SID, util.TableToJSON(inv), "[]", BPS.CONF.StartPoints, os.time() ))
	end
	
	return inv, points, pointsVIP, equip
end

-- Retrieve points from cache OR SQL
BPS.GetPoints 		= function( p, VIP, SQL )
	
	local isOnline 	= IsValid(p) and p:IsPlayer()
	local SID 		= isOnline and p:SteamID() or p	
	local typeStr 	= VIP and "PointsVIP" or "Points"
	local points
	
	if !SQL and isOnline and BPS.Players[p] then
		-- Retrieve from cache
		return BPS.Players[p][typeStr]
	else
		-- Retrieve from SQL
		return tonumber( sql.QueryValue( ( "SELECT %q FROM BPS_Player WHERE SID = %q" ):format( typeStr, SID ) ) )
	end
end

-- Retrieve inventory from cache OR SQL
BPS.GetInventory 	= function( p, SQL )

	local isOnline = IsValid(p) and p:IsPlayer()
	local SID = isOnline and p:SteamID() or p
	
	if isOnline and BPS.Players[p] and !SQL then
		-- Retrieve from cache
		return BPS.Players[p].Inv
	else
		-- Retrieve from SQL
		local inv = sql.QueryValue( ( "SELECT Inv FROM BPS_Player WHERE SID = %q" ):format( SID ) )
		
		if inv then return util.JSONToTable( inv ) end
	end
end

-- Delete from database
BPS.Deregister 		= function( p )
	
	sql.Query( ("DELETE FROM BPS_Player WHERE SID = %q"):format( p:SteamID() ) )
end

-- Give a player points
BPS.GivePoints 		= function( p, give, VIP )
	
	local isOnline 	= IsValid(p) and p:IsPlayer()
	local SID 		= isOnline and p:SteamID() or p
	local points 	= BPS.GetPoints( p, VIP )
	
	if !points then return end -- Lookup failed
	
	local total 	= math.max(0, points + give)
	local typeStr 	= VIP and "PointsVIP" or "Points"
	
	-- Write to cache
	if isOnline then BPS.Players[p][typeStr] = total end
	
	-- Write to SQL
	sql.Query( ( "UPDATE BPS_Player SET %q = %i WHERE SID = %q" ):format( typeStr, total, SID ) )
end

-- Give a player an item
BPS.GiveItem 		= function( p, item )
	
	local isOnline 	= IsValid(p) and p:IsPlayer()
	local SID 		= isOnline and p:SteamID() or p
	local inv 		= BPS.GetInventory( SID )
	
	-- Lookup failed, abort
	if !inv then return end
	
	-- Remove shop info
	item.Shop = nil
	
	-- Regenerate UID
	item.ID = 1 + math.max( table.maxn(inv.Accessories), table.maxn(inv.Playermodels), table.maxn(inv.Trails) )
	
	-- Insert item
	table.insert( inv[item.Category], item.ID, item )
	
	-- Update cache
	if isOnline then BPS.Players[p].Inv = inv end
	
	-- Write to SQL
	sql.Query( ( "UPDATE BPS_Player SET Inv = '%s' WHERE SID = %q" ):format( util.TableToJSON( inv ), SID ) )
end

-- Remove an item from a player
BPS.RemoveItem 		= function( p, ID )
	
	local isOnline 			= IsValid(p) and p:IsPlayer()
	local inv 				= BPS.GetInventory( p )
	local item, category 	= BPS.RetrievePlayerItem( p, ID )
	
	if !inv or !item then return end -- Lookup failed
	
	-- Delete item
	inv[category][ID] = nil
	
	-- Update cache
	if isOnline then BPS.Players[p].Inv = inv end
	
	-- Write to SQL
	sql.Query( ( "UPDATE BPS_Player SET Inv = '%s' WHERE SID = %q" ):format( util.TableToJSON( inv ), p:SteamID() ) )
	
	return item, category
end

-- Data cleaning for data corruption and version support
BPS.CleanItem 		= function( item, category )
	
	-- Remove voids
	for k, v in pairs( BPS.BlankItem( category ) ) do
		if !item[k] then item[k] = v end
	end
end

-- Modify an inventory item. If 'erase' is passed, this deletes attributes
BPS.ModifyItem 		= function( p, ID, itemData, erase )
	
	-- Fetch inventory and item index
	local inv 			= BPS.GetInventory( p )
	local _, category 	= BPS.RetrievePlayerItem( p, ID )
	
	-- Lookup failed
	if !category then return end
	
	-- Write to cache
	for k, v in pairs( itemData ) do 
		inv[category][ID][k] = !erase and v or nil
	end
	
	-- Write to SQL
	sql.Query( ( "UPDATE BPS_Player SET Inv = '%s' WHERE SID = %q" ):format( util.TableToJSON( inv ), p:SteamID() ) )
end

---------------
-- Equipping --
---------------

-- Retrieve equipped item(s) from cache OR SQL
BPS.GetEquipped	= function( p, ID, SQL )
	
	-- Retrieve from SQL
	if SQL then 
		return util.JSONToTable( sql.QueryValue( ( "SELECT Equip FROM BPS_Player WHERE SID = %q" ):format( p:SteamID() ) ) ) 
	end
	
	-- No ID passed. Return full list
	if !ID then return BPS.Players[p].Equipped or {} end
	
	-- No equipped items
	if !BPS.Players[p].Equipped then return end
	
	-- Return equipped state
	return BPS.Players[p].Equipped[ID]
end

-- Count equipped accessories
BPS.CountEquipped = function( p )
	
	local N = 0
	
	for _, category in pairs( BPS.GetEquipped( p ) ) do
		if category == "Accessories" then N = N + 1 end
	end
	
	return N
end

-- Set item equipped
BPS.SetEquipped = function( p, ID, category, doEquip )
	
	-- Fetch equip list
	local equip = BPS.GetEquipped( p )
	
	-- Set equip state
	equip[ID] = doEquip and category or nil
	
	-- Write to cache
	BPS.Players[p].Equipped = equip
	
	-- Write to SQL
	sql.Query( ( "UPDATE BPS_Player SET Equip ='%s' WHERE SID = %q" ):format( util.TableToJSON( equip ), p:SteamID() ) )
end

---------------------
-- Stock databases --
---------------------

-- Sort stock
BPS.SortStock 		= function( stock, isMarket )
	
	if isMarket then
		-- Market sort
		table.sort( stock, function(itemA, itemB) return itemA.Shop.SaleTime < itemB.Shop.SaleTime end )
	else
		-- Shop sort
		table.sort( stock, function(itemA, itemB) 
			if itemA.Shop.VIP ~= itemB.Shop.VIP then 
				return itemA.Shop.VIP
			else
				return itemA.Shop.Cost > itemB.Shop.Cost
			end
		end )
	end
	
	return stock
end

-- Retrieve stock from SQL
BPS.RetrieveStock 	= function( isMarket )
	
	local stock 		= sql.Query( ( "SELECT * FROM %s" ):format( isMarket and "BPS_Market" or "BPS_Shop" ) )
	local stockSort 	= {
		Accessories 	= {},
		Playermodels 	= {},
		Trails 			= {}
	}
	
	-- If there's no stock
	if !stock then return stockSort end
	
	-- Clean and populate
	for i, shopItem in pairs( stock ) do
		
		-- Format item
		local item 		= util.JSONToTable( shopItem.Item )
		item.ID 		= tonumber( shopItem.ID )
		item.Category 	= shopItem.Category
		item.Shop 		= {
			VIP 		= tobool( shopItem.VIP ),
			Cost 		= shopItem.Cost ~= "NULL" and tonumber(shopItem.Cost),
			Expiry 		= shopItem.Expiry ~= "NULL" and tonumber(shopItem.Expiry),
			BuysLeft 	= shopItem.BuysLeft ~= "NULL" and tonumber(shopItem.BuysLeft),
			SaleTime 	= shopItem.SaleTime ~= "NULL" and tonumber(shopItem.SaleTime),
			Bids 		= (shopItem.Bids and shopItem.Bids ~= "NULL") and util.JSONToTable( shopItem.Bids ),
			BidSID 		= shopItem.BidSID,
			SID 		= shopItem.SID,
			Nick 		= shopItem.Nick
		}
		
		-- Move to sorted table
		table.insert( stockSort[ item.Category ], item )
	end
	
	-- Sort
	for _, stock in pairs( stockSort ) do stock = BPS.SortStock( stock, isMarket ) end
	
	return stockSort
end

-- <MM> Add an item to the shop
BPS.AddToShop 		= function( category, item )
	
	-- Generate shop UID
	local UID = sql.QueryValue( "SELECT MAX(ID) FROM BPS_Shop" )
	UID = UID ~= "NULL" and UID + 1 or 1
	item.ID = UID
	
	-- Update + sort cache
	local stock = BPS.Stock.Shop[category]
	table.insert( stock, item )
	stock = BPS.SortStock( stock )
	
	-- Write to SQL
	sql.Query( ( "INSERT INTO BPS_Shop (ID, Item, Category, Cost, VIP, Expiry, BuysLeft) VALUES (%i, '%s', %q, %i, %i, %s, %s)" ):format( UID, util.TableToJSON(item), category, item.Shop.Cost, item.Shop.VIP and 1 or 0, item.Shop.Expiry or "NULL", item.Shop.BuysLeft or "NULL" ) )
end

-- Add an item to the market, assigns UID
BPS.AddToMarket		= function( p, item, category, cost )
	cost = nil
	-- Inject shop data
	item.Shop = {
		SID 		= p:SteamID(),
		Nick		= p:Nick(),
		Cost 		= cost or nil,
		Bids 		= !cost and {0} or nil,
		SaleTime	= os.time()
	}
	
	-- Generate market UID
	local UID = sql.QueryValue( "SELECT MAX(ID) FROM BPS_Market" )
	UID = UID ~= "NULL" and UID + 1 or 1
	item.ID = UID -- Overwrite inventory ID
	
	-- Update + sort cache
	local stock = BPS.Stock.Market[category]
	table.insert( stock, item )
	stock = BPS.SortStock( stock, true )
	
	-- Write to SQL
	sql.Query( ( "INSERT INTO BPS_Market (ID, SID, Nick, Item, Category, Cost, SaleTime, Bids) VALUES (%i, %q, %q, '%s', %q, %s, %i, %q)" ):format( UID, item.Shop.SID, item.Shop.Nick, util.TableToJSON( item ), category, item.Shop.Cost or "NULL", item.Shop.SaleTime, !cost and "[0.0]" or "NULL" ) )
end

-- Verifier. Check if market is saturated, or player has hit their item limit
BPS.CanAddToMarket	= function( p )
	
	local SID = p:SteamID()
	local pCount = 0
	local tCount = 0
	
	-- Count market items
	for _, stock in pairs(BPS.Stock.Market) do
		for _, item in pairs(stock) do
			
			tCount = tCount + 1
			if item.SID == SID then pCount = pCount + 1 end -- Count player owned market items
		end
	end
	
	if pCount >= BPS.CONF.MarketLimitPlayer then return false end
	if tCount >= BPS.CONF.MarketLimitTotal then return false, true end
	return true
end

-- <MM> Modify a shop item
BPS.ModifyShopItem 	= function( ID, modData )
	
	-- Retrieve item
	local item, category, idx = BPS.RetrieveItem( ID )
	
	-- Lookup failed
	if !item then return end
	
	-- Overwrite provided keys
	for k, v in pairs( item ) do item[k] = modData[k] or v end
	
	-- Write to cache
	local shop = BPS.Stock.Shop[category]
	shop[idx] = item
	
	-- Sort
	shop = BPS.SortStock( shop )
	
	-- Write changes
	sql.Query( ( "UPDATE BPS_Shop SET Item = '%s', Category = %q, Cost = %i, VIP = %i, Expiry = %s, BuysLeft = %s WHERE ID == %i" ):format( util.TableToJSON( item ), category, item.Shop.Cost, item.Shop.VIP and 1 or 0, item.Shop.Expiry or "NULL", item.Shop.BuysLeft or "NULL", ID ) )
end

-- <MM> Remove an item from the shop. Also used by expiry checker
BPS.RemoveFromShop 	= function( ID, category, idx )
	
	-- Remove from cache
	BPS.Stock.Shop[category][idx] = nil
	
	-- Write to SQL
	sql.Query( "DELETE FROM BPS_Shop WHERE ID == " .. ID )
end

-- Remove an item from the market
BPS.RemoveFromMarket = function( ID, giveBack )
	
	-- Fetch the item
	local item, category, idx = BPS.RetrieveItem( ID, true )
	
	-- Lookup failed
	if !item then return end
	
	local SID = item.Shop.SID
	
	-- Return the item
	if giveBack ~= false then
		
		item.Shop = nil -- Bin shop info
		BPS.GiveItem( player.GetBySteamID(SID) or SID, item, category )
	end
	
	-- Write to cache
	local stock = BPS.Stock.Market[category]
	for i, item in pairs(stock) do
		if item.ID == ID then
			table.remove( stock, i )
		break end
	end
	
	-- Sort cache
	stock = BPS.SortStock( stock, true )
	
	-- Write to SQL
	sql.Query( "DELETE FROM BPS_Market WHERE ID == " .. ID )
end

-- Search for expired items
BPS.FindExpiredItem = function( isMarket )
	
	local timeNow 	= os.time()
	
	--[[ SQL: Find ID of an expired item, if any
	if isMarket then
		return sql.QueryValue( ("SELECT ID FROM BPS_Market WHERE SaleTime <= %i"):format( timeNow - BPS.CONF.MarketExpireTime * 3600 ) )
	else
		return sql.QueryValue( ("SELECT ID FROM BPS_Shop WHERE Expiry <= %i"):format( timeNow ) )
	end]]--
	
	-- Search cache
	if isMarket then
		for _, stock in pairs(BPS.Stock.Market) do
			for _, item in pairs(stock) do
				-- Check if market item is expired, or if bidding is over
				if (item.Shop.Cost and timeNow >= item.Shop.SaleTime + BPS.CONF.MarketExpireTime * 3600) or (!item.Shop.Cost and timeNow >= item.Shop.SaleTime + BPS.CONF.BidDuration * 3600) then
					return item
				end
			end
		end
	else
		for _, stock in pairs(BPS.Stock.Shop) do
			for _, item in pairs(stock) do
				-- Check if shop item is expired
				if item.Shop.Expiry and timeNow >= item.Shop.Expiry then
					return item
				end
			end
		end
	end
end

-------------
-- Bidding --
-------------

-- Place a bid on an item
BPS.PlaceBid 		= function( p, ID, category, idx, bid )
	
	-- Retrieve current bids
	local item = BPS.Stock.Market[category][idx]
	local bids = item.Shop.Bids
	
	-- Update bids list
	if bids[1] == 0 then 
		bids = {bid}
	else
		table.insert(bids, 1, bid)
		while #bids > 4 do
			table.remove(bids)
		end
	end
	
	-- Update cache
	local SID = p:SteamID()
	item.Shop.BidSID = SID
	item.Shop.Bids = bids
	
	-- Write to SQL
	sql.Query( ( "UPDATE BPS_Market SET Bids = '%s', BidSID = %q WHERE ID == %i" ):format( util.TableToJSON(bids), SID, ID ) )
	
	return bids
end

-----------
-- MySQL --
-----------

if !BPS.CONF.UseMySQL then return end

-- Stock look-up
BPS.CheckItemExists	= function( ID, isMarket )
	
	return sql.QueryValue( "SELECT 1 FROM BPS_" .. (isMarket and "Market" or "Shop") .. " WHERE ID == " .. ID ) and true or false
end
