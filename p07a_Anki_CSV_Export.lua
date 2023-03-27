--[[
 * ReaScript Name: Export markers and regions to tab-delimited CSV file
 * Instructions: 
 * Author: p07a
 * Repository:
 * Repository URI: 
 * Links
 * Licence: MIT
 * REAPER: 6.0+
 * Version: 0.0
--]]

--[[
 * Changelog:

--]]

local delims = {
  [", (comma)"]      = ",",
  ["\\t (tab)"]      = "\t",
  [" (space)"]       = " ",
  ["_ (underscore)"] = "_",
  ["- (hyphen)"]     = "-",
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

-- Main section

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

local dataOut = {}
dataKeysSorted = {}
outputDelimiter = '\\t (tab)'
inputDelimiter = '- (hyphen)'
formatPattern = '[sound:%s.mp3]' 
maxNoteSplit = 1

function itemPropV(item, attr)
  return reaper.GetMediaItemInfo_Value(item,attr)
end

function itemPropS(item, attr)
  rv, str = reaper.GetSetMediaItemInfo_String(item,attr,'',false)
  if rv then
    return str
  else
    return ""
  end
end

function takePropV(take, attr)
  return reaper.GetMediaItemTakeInfo_Value(take,attr)
end

function takePropS(take, attr)
  rv, str = reaper.GetSetMediaItemTakeInfo_String(take,attr,'', false)
  if rv then
    return str
  else
    return ""
  end
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

    
    dataOut[j] = {}
    local entry = {}
    
    entry.position = itemPropV(mItem,"D_POSITION")
    entry.name = string.format(formatPattern, takePropS(mTake, "P_NAME"))
    entry.notes = {}
    
    for e in string.gmatch(itemPropS(mItem, "P_NOTES"),"[^".. delims[inputDelimiter] .."]+") do 
      -- insert trimmed splitted note
      entry.notes[#entry.notes+1] = e:gsub("^%s*(.-)%s*$", "%1")
    end
    maxNoteSplit = math.max(maxNoteSplit,#entry.notes)
 
    dataOut[j] = entry
     
    i = i+1
  until i == max
  
  -- sort the entry's keys.
  for k in pairs(dataOut[1]) do table.insert(dataKeysSorted,k) end
  table.sort(dataKeysSorted)
  
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
  if ImGui.BeginCombo(ctx, 'MediaItem\'s note splitting delimiter', inputDelimiter) then
    for k,v in pairs(delims) do
      local isSelected = k == inputDelimiter 
      if ImGui.Selectable(ctx, k, isSelected) then
        inputDelimiter = k
      end
      
      if isSelected then
        ImGui.SetItemDefaultFocus(ctx)
      end
    end
    ImGui.EndCombo(ctx)
  end
  
  ImGui.SetNextItemWidth(ctx,250)
  if ImGui.BeginCombo(ctx, 'output joining delimiter', outputDelimiter) then
    for k,v in pairs(delims) do
      local isSelected = k == outputDelimiter 
      if ImGui.Selectable(ctx, k, isSelected) then
        outputDelimiter = k
      end
      
      if isSelected then
        ImGui.SetItemDefaultFocus(ctx)
      end
    end
    ImGui.EndCombo(ctx)
  end
  
  ImGui.SetNextItemWidth(ctx,250)
  rv,formatPattern = ImGui.InputText(ctx, 'format take name', formatPattern)
  
  ImGui.SeparatorText(ctx,"Actions")
  
  if ImGui.Button(ctx,"Open Render...") then
    reaper.Main_OnCommand(40015,0)
  end

  ImGui.SameLine(ctx)
  
  if ImGui.Button(ctx, "Export CSV") then
    reaper.defer(Save)
  end
  ImGui.Spacing(ctx)
  
  ImGui.SeparatorText(ctx,"Preview")
  
  if ImGui.Button(ctx, "Refresh") then
    reaper.defer(updateData())
  end
  
  if ImGui.BeginTable(ctx,'previewTable', maxNoteSplit+2, ImGui.TableFlags_RowBg() | ImGui.TableFlags_Borders()) then
  
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
     export(f,table.concat(line,delims[outputDelimiter]))
   end
   
   -- CLOSE FILE
   f:close() -- never forget to close the file
   end

end

-- reaper.defer(Save)




--[[
rv,strng = reaper.GetSetMediaItemInfo_String(reaper.GetMediaItem(0,0),"P_NOTES",'', false)
rv, image, imageFlags = reaper.BR_GetMediaItemImageResource(reaper.GetMediaItem(0,0))
Msg(""..strng)
Msg(image)
--]]


