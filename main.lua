local M = {}

local DEFAULT_CONFIG = {
	geometry = "margin=0.35in",
	raster_dpi = "192",
}

local function config_value(opts, ...)
	if type(opts) ~= "table" then
		return nil
	end

	for i = 1, select("#", ...) do
		local value = opts[select(i, ...)]
		if value ~= nil and value ~= "" then
			return value
		end
	end
end

local function normalize_config(opts)
	return {
		geometry = config_value(opts, "geometry") or DEFAULT_CONFIG.geometry,
		raster_dpi = tostring(config_value(opts, "raster_dpi", "raster-dpi") or DEFAULT_CONFIG.raster_dpi),
	}
end

local function merge_config(base, overrides)
	base = normalize_config(base)
	return {
		geometry = config_value(overrides, "geometry") or base.geometry,
		raster_dpi = tostring(config_value(overrides, "raster_dpi", "raster-dpi") or base.raster_dpi),
	}
end

local config = normalize_config()

local load_config = type(ya) == "table" and ya.sync and ya.sync(function(st)
	return st.config
end) or function()
	return config
end

local function current_config(args)
	return merge_config(load_config(), args)
end

function M:setup(opts)
	config = normalize_config(opts)
	self.config = config
end

local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function dirname(path)
	return path:match("^(.*)/[^/]+$") or "."
end

local function cache_root()
	local base = os.getenv("XDG_CACHE_HOME")
	if not base or base == "" then
		local home = os.getenv("HOME")
		base = home and (home .. "/.cache") or "/tmp"
	end
	return base .. "/yazi/md-preview"
end

local function ensure_dir(path)
	local output, err = Command("mkdir"):arg({ "-p", path }):output()
	if not output then
		return false, Err("Failed to start `mkdir`, error: %s", err)
	elseif not output.status.success then
		return false, Err("Failed to create cache directory, stderr: %s", output.stderr)
	end
	return true
end

local function file_exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function cache_signature_path(cache)
	return tostring(cache) .. ".md-preview"
end

local function cache_signature_matches(cache, signature)
	local f = io.open(cache_signature_path(cache), "rb")
	if not f then
		return false
	end

	local cached = f:read("*a")
	f:close()
	return trim(cached) == signature
end

local function write_cache_signature(cache, signature)
	local f = io.open(cache_signature_path(cache), "wb")
	if f then
		f:write(signature)
		f:close()
	end
end

local function cache_key(path, cfg)
	local script = [[
if meta=$(stat -c '%s:%Y' "$1" 2>/dev/null); then
	:
elif meta=$(stat -f '%z:%m' "$1" 2>/dev/null); then
	:
else
	exit 1
fi

printf '%s\n%s\n%s\n%s\n' "$1" "$2" "$3" "$meta" |
if command -v sha1sum >/dev/null 2>&1; then
	sha1sum | cut -d' ' -f1
else
	shasum -a 1 | cut -d' ' -f1
fi
]]
	local output, err = Command("sh"):arg({ "-c", script, "sh", path, cfg.geometry, cfg.raster_dpi }):output()
	if not output then
		return nil, Err("Failed to start cache-key shell, error: %s", err)
	elseif not output.status.success then
		return nil, Err("Failed to compute Markdown cache key, stderr: %s", output.stderr)
	end
	return trim(output.stdout)
end

local function pdf_path(job, cfg)
	local path = tostring(job.file.path)
	local root = cache_root()
	local ok, err = ensure_dir(root)
	if not ok then
		return nil, err
	end

	local key, key_err = cache_key(path, cfg)
	if not key then
		return nil, key_err
	end
	return root .. "/" .. key .. ".pdf"
end

local function compile_pdf(job, pdf, cfg)
	local path = tostring(job.file.path)
	local output, err = Command("pandoc")
		:cwd(dirname(path))
		:arg({
			path,
			"--from=markdown+tex_math_dollars+tex_math_single_backslash",
			"--pdf-engine=xelatex",
			"-V",
			"geometry:" .. cfg.geometry,
			"-o",
			pdf,
		})
		:output()

	if not output then
		return false, Err("Failed to start `pandoc`, error: %s", err)
	elseif not output.status.success then
		return false, Err("Failed to render Markdown with Pandoc, stderr: %s", output.stderr)
	end
	return true
end

local function page_count(pdf)
	local output, err = Command("pdfinfo"):arg({ pdf }):output()
	if not output then
		return nil, Err("Failed to start `pdfinfo`, error: %s", err)
	elseif not output.status.success then
		return nil, Err("Failed to inspect rendered PDF, stderr: %s", output.stderr)
	end
	return tonumber(output.stdout:match("Pages:%s+(%d+)"))
end

local function error_widget(job, err)
	ya.preview_widget(job, ui.Text(tostring(err)):area(job.area):wrap(ui.Wrap.YES))
end

local function preview_areas(area)
	if area.h <= 1 then
		return area
	end

	return ui.Rect({ x = area.x, y = area.y, w = area.w, h = area.h - 1 }),
		ui.Rect({ x = area.x, y = area.y + area.h - 1, w = area.w, h = 1 })
end

local function page_indicator(job, pages)
	return string.format("Page %d / %d", job.skip + 1, pages)
end

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err, bound, pages = self:preload(job, cache, current_config(job.args))
	if bound and bound > 0 then
		return ya.emit("peek", { bound - 1, only_if = job.file.url, upper_bound = true })
	elseif not ok or err then
		return error_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

	local image_area, footer_area = preview_areas(job.area)
	local _, show_err = ya.image_show(cache, image_area)
	ya.preview_widget(job, show_err)
	if not show_err and footer_area and pages then
		ya.preview_widget(job, ui.Text(page_indicator(job, pages)):area(footer_area))
	end
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

function M:preload(job, cache, cfg)
	local pdf, path_err = pdf_path(job, cfg)
	if not pdf then
		return false, path_err
	elseif not file_exists(pdf) then
		local ok, compile_err = compile_pdf(job, pdf, cfg)
		if not ok then
			return false, compile_err
		end
	end

	local pages, pages_err = page_count(pdf)
	if not pages then
		return false, pages_err
	elseif job.skip + 1 > pages then
		return true, nil, pages, pages
	elseif fs.cha(cache) and cache_signature_matches(cache, pdf) then
		return true, nil, nil, pages
	end

	local page = tostring(job.skip + 1)
	local output, err = Command("pdftoppm")
		:arg({
			"-f",
			page,
			"-l",
			page,
			"-singlefile",
			"-png",
			"-r",
			cfg.raster_dpi,
			pdf,
			tostring(cache),
		})
		:output()

	if not output then
		return false, Err("Failed to start `pdftoppm`, error: %s", err)
	elseif not output.status.success then
		local bound = job.skip > 0 and tonumber(output.stderr:match("the last page %((%d+)%)"))
		return false, Err("Failed to convert rendered PDF to image, stderr: %s", output.stderr), bound
	end

	local ok, err = ya.image_precache(Url(tostring(cache) .. ".png"), cache)
	if ok then
		write_cache_signature(cache, pdf)
	end
	return ok, err, nil, pages
end

return M
