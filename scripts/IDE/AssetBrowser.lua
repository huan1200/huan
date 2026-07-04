-- ============================================================
-- IDE/AssetBrowser.lua - 资源浏览器
-- 功能: 图片/音频/脚本资源浏览、预览、拖拽使用
-- ============================================================
local Config = require("IDE.Config")
local EventBus = require("IDE.EventBus")

local AssetBrowser = {}

AssetBrowser._assets = {}
AssetBrowser._categories = {
  image = { name = "图片", icon = "IMG", extensions = {".png", ".jpg", ".jpeg", ".bmp", ".gif"} },
  audio = { name = "音频", icon = "SND", extensions = {".ogg", ".wav", ".mp3"} },
  script = { name = "脚本", icon = "LUA", extensions = {".lua"} },
  font = { name = "字体", icon = "FNT", extensions = {".ttf", ".otf"} },
  data = { name = "数据", icon = "DAT", extensions = {".json", ".xml", ".csv"} },
  other = { name = "其他", icon = "OTH", extensions = {} },
}
AssetBrowser._selectedAsset = nil
AssetBrowser._searchText = ""
AssetBrowser._currentCategory = "all"
AssetBrowser._thumbnailCache = {}
AssetBrowser._thumbSize = 64
AssetBrowser._scrollY = 0

function AssetBrowser:init()
  self._assets = {}
  self._selectedAsset = nil
  self._searchText = ""
  self._currentCategory = "all"
  self._thumbnailCache = {}
  self._scrollY = 0
  self:ScanAssets()
end

-- 扫描 assets 目录
function AssetBrowser:ScanAssets()
  self._assets = {}
  local dirs = {"assets/image", "assets/audio", "assets/sfx", "scripts", "Fonts"}

  for _, dir in ipairs(dirs) do
    if fileSystem:DirExists(dir) then
      local files = fileSystem:ScanDir(dir, "*.*", SCAN_FILES, true)
      if files then
        for _, fileName in ipairs(files) do
          self:_addAsset(dir .. "/" .. fileName, 0)
        end
      end
    end
  end

  -- 排序
  table.sort(self._assets, function(a, b) return a.path < b.path end)
  print(string.format("[AssetBrowser] 扫描完成，发现 %d 个资源", #self._assets))
end

function AssetBrowser:_addAsset(path, size)
  local ext = path:match("%.[^%.]+$") or ""
  ext = ext:lower()

  local category = "other"
  for catName, catInfo in pairs(self._categories) do
    for _, catExt in ipairs(catInfo.extensions) do
      if ext == catExt then
        category = catName
        break
      end
    end
    if category ~= "other" then break end
  end

  local name = path:match("[^/]+$") or path
  local asset = {
    id = Config.generateId("asset"),
    path = path,
    name = name,
    category = category,
    size = size or 0,
    ext = ext,
    usedCount = 0,
  }
  table.insert(self._assets, asset)
end

-- 获取过滤后的资源列表
function AssetBrowser:GetFilteredAssets()
  local result = {}
  for _, asset in ipairs(self._assets) do
    local matchCategory = (self._currentCategory == "all") or (asset.category == self._currentCategory)
    local matchSearch = (self._searchText == "") or
      (asset.name:lower():find(self._searchText:lower(), 1, true) ~= nil) or
      (asset.path:lower():find(self._searchText:lower(), 1, true) ~= nil)
    if matchCategory and matchSearch then
      table.insert(result, asset)
    end
  end
  return result
end

-- 获取分类统计
function AssetBrowser:GetCategoryCounts()
  local counts = { all = #self._assets }
  for _, asset in ipairs(self._assets) do
    counts[asset.category] = (counts[asset.category] or 0) + 1
  end
  return counts
end

-- 选中资源
function AssetBrowser:SelectAsset(assetId)
  for _, asset in ipairs(self._assets) do
    if asset.id == assetId then
      self._selectedAsset = asset
      EventBus:emit("asset.selected", asset)
      return asset
    end
  end
  self._selectedAsset = nil
  return nil
end

function AssetBrowser:GetSelectedAsset()
  return self._selectedAsset
end

-- 设置搜索文本
function AssetBrowser:SetSearch(text)
  self._searchText = text or ""
  self._scrollY = 0
end

-- 设置分类过滤
function AssetBrowser:SetCategory(cat)
  self._currentCategory = cat or "all"
  self._scrollY = 0
end

-- 获取资源信息
function AssetBrowser:GetAssetByPath(path)
  for _, asset in ipairs(self._assets) do
    if asset.path == path then return asset end
  end
  return nil
end

-- 标记资源被使用
function AssetBrowser:MarkUsed(path)
  local asset = self:GetAssetByPath(path)
  if asset then asset.usedCount = asset.usedCount + 1 end
end

-- 刷新
function AssetBrowser:Refresh()
  self:ScanAssets()
end

return AssetBrowser
