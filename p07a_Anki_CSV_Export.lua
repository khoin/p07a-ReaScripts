--[[
 * ReaScript Name: Export MediaItem and its notes to tab-delimited CSV file
 * Instructions: This opens up a GUI for you to choose the parameters and includes a way to format take names
 * Author: p07a
 * Repository: p07a-ReaScripts
 * Repository URI: https://github.com/khoin/p07a-ReaScripts/
 * Links
 * License: Public Domain
 * REAPER: 6.0
 * Version: 0.1
--]]

--[[
 * Changelog:
    v 0.1
      initial
--]]

-- To change the default parameters, please go to STATE just at the beginning of the Process Section below.

local delims = {
  [", (comma)"]      = ",",
  ["\\t (tab)"]      = "\t",
  [" (space)"]       = " ",
  ["_ (underscore)"] = "_",
  ["- (hyphen)"]     = "-",
}

local sortFuncs = {
  ["Position"]    = function(a,b) return a.position < b.position end,
  ["Default"]     = function(a,b) return true end, -- for some reason Lua doesnt accept this is a valid sort func
  ["Take Name"]   = function(a,b) return a.name < b.name end,
}

local ImGui = {}
for name, func in pairs(reaper) do
  name = name:match('^ImGui_(.+)$')
  if name then ImGui[name] = func end
end

local ctx

function Msg(val)
  reaper.ShowConsoleMsg(tostring(val).."\n")
end

function export(f, variable)
  f:write(variable)
  f:write("\n")
end

-- Checks
local failed
if not reaper.JS_Dialog_BrowseForSaveFile then
  failed = 1
  Msg("Please install JS_ReaScript REAPER extension, available in Reapack extension, under ReaTeam Extensions repository.")
end

if not reaper.ImGui_Begin then
  failed = 1 
  Msg("Please install ImGui REAPER extension, via Reapack extension, under ReaTeam Extension repo.")
end

-- Main Section ---------------

function Main() 
  if failed then return end

  ctx = ImGui.CreateContext('Anki CSV Export')
  updateData()
  reaper.defer(GuiLoop)
end

reaper.defer(Main)

function GuiLoop()
  open = GuiRender(true)
  
  if open then
    reaper.defer(GuiLoop)
  end
end

-- Process Section -------------

local dataOut = {}
dataKeysSorted = {}

STATE = {}
STATE.outputDelimiter = '\\t (tab)'
STATE.inputDelimiter = '- (hyphen)'
STATE.formatPattern = '[sound:%s.mp3]' 
STATE.sort = "Position"
maxNoteSplit = 1

function itemPropV(item, attr)
  return reaper.GetMediaItemInfo_Value(item,attr)
end

function itemPropS(item, attr)
  rv, str = reaper.GetSetMediaItemInfo_String(item,attr,'', false)
  return not rv and "" or str
end

function takePropV(take, attr)
  return reaper.GetMediaItemTakeInfo_Value(take,attr)
end

function takePropS(take, attr)
  rv, str = reaper.GetSetMediaItemTakeInfo_String(take,attr,'', false)
  return not rv and "" or str
end

function trackPropS(take, attr)
  rv, str = reaper.GetSetMediaTrackInfo_String(take,attr,'', false)
  return not rv and "" or str
end

function updateData()
  dataOut = {}
  dataKeysSorted = {}
  maxNoteSplit = 1
  
  local max = reaper.CountMediaItems(0)
  i = 0
  repeat
    local j = i + 1
    local mItem = reaper.GetMediaItem(0,i)
    local mTake = reaper.GetMediaItemTake(mItem, reaper.GetMediaItemInfo_Value(mItem,"I_CURTAKE"))
    local mTrack = reaper.GetMediaItemTrack(mItem)
    
    dataOut[j] = {}
    local entry = {}
    
    entry.position = itemPropV(mItem,"D_POSITION")
    entry.name = string.format(STATE.formatPattern, takePropS(mTake, "P_NAME"))
    entry.track = trackPropS(mTrack, "P_NAME")
    entry.notes = {}
    
    for e in string.gmatch(itemPropS(mItem, "P_NOTES"),"[^".. delims[STATE.inputDelimiter] .."]+") do 
      -- insert trimmed splitted note
      entry.notes[#entry.notes+1] = e:gsub("^%s*(.-)%s*$", "%1")
    end
    
    maxNoteSplit = math.max(maxNoteSplit,#entry.notes)
 
    dataOut[j] = entry
     
    i = i+1
  until i == max
  
  -- sort the entry's keys since pairs() does not guarantee order consistency.
  for k in pairs(dataOut[1]) do table.insert(dataKeysSorted,k) end
  table.sort(dataKeysSorted)
  
  -- sort by position, remove this line if you'd want to sort by track
  if not (STATE.sort == "Default") then table.sort(dataOut, sortFuncs[STATE.sort]) end

end

-- GUI RENDER ----------------------

function keyValueCombo(ctx, range, selection)
  for k,v in pairs(range) do
    local isSelected = k == STATE[selection]
    if ImGui.Selectable(ctx, k, isSelected) then
      STATE[selection] = k
    end
    
    if isSelected then
      ImGui.SetItemDefaultFocus(ctx)
    end
  end
end

function GuiRender(open)
  local rv = nil
  
  local main_viewport = ImGui.GetMainViewport(ctx)
  local workpos = {ImGui.Viewport_GetWorkPos(main_viewport)}  
  
  ImGui.SetNextWindowPos(ctx, workpos[1]+100, workpos[2]+100, ImGui.Cond_FirstUseEver() )
  ImGui.SetNextWindowSize(ctx, 530, 530, ImGui.Cond_FirstUseEver() )
  
  rv,open = ImGui.Begin(ctx, 'CSV Export', open, ImGui.WindowFlags_TopMost())
  
  if not rv then return open end
  
  ImGui.SetNextItemWidth(ctx,250)
  if ImGui.BeginCombo(ctx, 'MediaItem\'s note splitting delimiter', STATE.inputDelimiter) then
    keyValueCombo(ctx, delims, 'inputDelimiter')
    ImGui.EndCombo(ctx)
  end
  
  ImGui.SetNextItemWidth(ctx,250)
  if ImGui.BeginCombo(ctx, 'output joining delimiter', STATE.outputDelimiter) then
    keyValueCombo(ctx, delims, 'outputDelimiter')
    ImGui.EndCombo(ctx)
  end
  
  ImGui.SetNextItemWidth(ctx,250)
  if ImGui.BeginCombo(ctx, 'Sort', STATE.sort) then
    keyValueCombo(ctx, sortFuncs, 'sort')
    ImGui.EndCombo(ctx)
  end
  
  ImGui.SetNextItemWidth(ctx,250)
  rv,STATE.formatPattern = ImGui.InputText(ctx, 'format take name', STATE.formatPattern)
  
  ImGui.Spacing(ctx)
  ImGui.SeparatorText(ctx,"Actions") ------------------------------
  if ImGui.Button(ctx,"Open Render...") then reaper.Main_OnCommand(40015,0) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Export CSV") then reaper.defer(Save) end
  
  ImGui.Spacing(ctx)
  ImGui.SeparatorText(ctx,"Preview") ------------------------------
  
  if ImGui.Button(ctx, "Refresh") then reaper.defer(updateData())end
  
  if ImGui.BeginTable(ctx,'previewTable', maxNoteSplit+#dataKeysSorted-1, 
                      ImGui.TableFlags_RowBg() | ImGui.TableFlags_Borders()) then
  
    for i, entry in ipairs(dataOut) do
      ImGui.TableNextRow(ctx)
      
      for _,k in ipairs(dataKeysSorted) do
        local v = entry[k]
        if k == 'notes' then
          for n=1,maxNoteSplit do
            ImGui.TableNextColumn(ctx)
            ImGui.Text(ctx, v[n])
          end
        else
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, v)
        end
      end
    end
    
    ImGui.EndTable(ctx)
  end
 
  
  ImGui.End(ctx)
  
  return open
end

-- Call using reaper.defer
function Save()
  
  retval, file = reaper.JS_Dialog_BrowseForSaveFile( "Save CSV", '', "", 'csv files (.csv)\0*.csv\0All Files (*.*)\0*.*\0' )
  
  if retval and file ~= '' then
   if not file:find('.csv') then file = file .. ".csv" end
   
   local f = io.open(file, "w")
   
   for i, entry in ipairs(dataOut) do
     local line = {}
     
     for _,k in ipairs(dataKeysSorted) do
       local v = entry[k]
       if k == 'notes' then
         for n=1,maxNoteSplit do
           table.insert(line, v[n] and v[n] or "")
         end
       else
         table.insert(line,v)
       end
     end
     export(f,table.concat(line,delims[STATE.outputDelimiter]))
   end
   
   -- CLOSE FILE
   f:close() -- never forget to close the file
   end

end

--[[
rv,strng = reaper.GetSetMediaItemInfo_String(reaper.GetMediaItem(0,0),"P_NOTES",'', false)
rv, image, imageFlags = reaper.BR_GetMediaItemImageResource(reaper.GetMediaItem(0,0))
Msg(""..strng)
Msg(image)
--]]


