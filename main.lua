local M = {}

local GEOMETRY = "margin=0.35in"
local RASTER_DPI = "192"

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
	return base .. "/yazi/md2preview"
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

local function cache_key(path)
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
	local output, err = Command("sh"):arg({ "-c", script, "sh", path, GEOMETRY, RASTER_DPI }):output()
	if not output then
		return nil, Err("Failed to start cache-key shell, error: %s", err)
	elseif not output.status.success then
		return nil, Err("Failed to compute Markdown cache key, stderr: %s", output.stderr)
	end
	return trim(output.stdout)
end

local function pdf_path(job)
	local path = tostring(job.file.path)
	local root = cache_root()
	local ok, err = ensure_dir(root)
	if not ok then
		return nil, err
	end

	local key, key_err = cache_key(path)
	if not key then
		return nil, key_err
	end
	return root .. "/" .. key .. ".pdf"
end

local function compile_pdf(job, pdf)
	local path = tostring(job.file.path)
	local output, err = Command("pandoc")
		:cwd(dirname(path))
		:arg({
			path,
			"--from=markdown+tex_math_dollars+tex_math_single_backslash",
			"--pdf-engine=xelatex",
			"-V",
			"geometry:" .. GEOMETRY,
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

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err, bound = self:preload(job, cache)
	if bound and bound > 0 then
		return ya.emit("peek", { bound - 1, only_if = job.file.url, upper_bound = true })
	elseif not ok or err then
		return error_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

	local _, show_err = ya.image_show(cache, job.area)
	ya.preview_widget(job, show_err)
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

function M:preload(job, cache)
	if fs.cha(cache) then
		return true
	end

	local pdf, path_err = pdf_path(job)
	if not pdf then
		return false, path_err
	elseif not file_exists(pdf) then
		local ok, compile_err = compile_pdf(job, pdf)
		if not ok then
			return false, compile_err
		end
	end

	local pages, pages_err = page_count(pdf)
	if not pages then
		return false, pages_err
	elseif job.skip + 1 > pages then
		return true, nil, pages
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
			RASTER_DPI,
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

	return ya.image_precache(Url(tostring(cache) .. ".png"), cache)
end

return M
