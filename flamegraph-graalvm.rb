#!/usr/bin/env ruby

require 'json'

class SVGGenerator

  def initialize
    @svg = ''
  end

  def header(width, height)
    enc_attr = @encoding ? " encoding=#{@encoding}" : ''
    @svg << <<-EOF
<?xml version="1.0"#{enc_attr} standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="#{width}" height="#{height}" onload="init(evt)" viewBox="0 0 #{width} #{height}" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<!-- Flame graph stack visualization. See https://github.com/brendangregg/FlameGraph for latest version, and http://www.brendangregg.com/flamegraphs.html for examples. -->
<!-- NOTES: #{@notestext} -->
EOF
  end

  def include(data = '')
    @svg << data
  end

  def color_allocate(r, g, b)
    "rgb(#{r}, #{g}, #{b})"
  end

  def group_start(**attributes)
    keys = [:class, :style, :onmouseover, :onmouseout, :onclick, :id]
    # For each key in atttributes generate a string "name=value"
    formatted_attrs = []
    keys.each do |key|
      value = attributes[key]
      if value
        formatted_attrs << "#{key}=\"#{value}\""
      end
    end

    # Include extra attribute info if present
    formatted_attrs << attributes[:g_extra] if attributes[:g_extra]
    joined_attrs = formatted_attrs.join(' ')
    @svg << "<g #{joined_attrs}>\n"
    # include the title if present
    @svg << "<title>#{attributes[:title]}</title>" if attributes[:title]

    if attributes[:href]
      @svg << "<a xlink:href=#{attributes[:href]}"
      @svg << " target=#{attributes[:target] || '_top'}"
      if attributes[:a_extra]
        attributes[:a_extra].each do |x|
          @svg << " #{x}"
        end
      end
      @svg << ">\n"
    end
  end

  def group_end(**attributes)
    if attributes[:href]
      @svg << "</a>\n"
    end
    @svg << "</g>\n"
  end

  def filled_rectangle(x1, y1, x2, y2, fill, extra='')
    w = x2 - x1
    h = y2 - y1
    @svg << <<-EOF
<rect x="#{x1}" y="#{y1}" width="#{w}" height="#{h}" fill="#{fill}" #{extra} />\n
EOF
  end

  def ttf_string(color, font, size, angle, x, y, str, loc='left', extra='')
        @svg << <<-EOF
<text text-anchor="#{loc}" x="#{x}" y="#{y}" font-size="#{size}" font-family="#{font}" fill="#{color}" #{extra} >#{str}</text>\n
EOF
  end

  def close
    @svg << '</svg>'
  end

  def output
    @svg
  end

  def escape(str)
    str = str.gsub('&', '&amp;')
	str = str.gsub('<', '&lt;')
	str = str.gsub('>', '&gt;')
  end

end

class FlameGraph

  def initialize(tree, svg, **attributes)
    @tree = tree
    @fonttype = "Verdana"
    @imagewidth = 1200.0         # max width, pixels
    @frameheight = 16.0          # max height is dynamic
    @fontsize = 12.0             # base text size
    @fontwidth = 0.59            # avg width relative to fontsize
    @minwidth = 0.01              # min function width, pixels
    @nametype = "Function:"      # what are the names in the data?
    @countname = "samples"       # what are the counts in the data?
    @colors = "hot"              # color theme
    @bgcolor1 = "#eeeeee"        # background color gradient start
    @bgcolor2 = "#eeeeb0"        # background color gradient stop
    @nameattrfile                # file holding function attributes
    @timemax                     # (override the) sum of the counts
    @factor = 1.0                # factor to scale counts by
    @hash = nil                  # color by function name
    @palette = nil               # if we use consistent palettes (default off
    @palette_map = []            # palette map hash
    @pal_file = "palette.map"    # palette map file name
    @stackreverse = nil          # reverse stack order, switching merge end
    @inverted = nil              # icicle graph
    @flamechart = nil            # produce a flame chart (sort by time, do not merge stacks)
    @negate = nil                # switch differential hues
    @titletext = ""              # centered heading
    @titledefault = "Flame Graph" 	# overwritten by --title
    @titleinverted = "Icicle Graph" 	#   "    "
    @searchcolor = "rgb(230,0,230)" 	# color for search highlighting
    @notestext = "" 		# embedded notes in SVG
    @subtitletext = "" 		# second level title (optional)
    @help = nil

    @by_language = attributes[:by_language]
    @by_compilation = attributes[:by_compilation]

    @nameattr = {}
    @svg = svg

    # internals
    @ypad1 = @fontsize * 3       # pad top, include title
    @ypad2 = @fontsize * 2 + 10  # pad bottom, include labels
    @ypad3 = @fontsize * 2       # pad top, include subtitle (optional)
    @xpad = 10.0                 # pad lefm and right
    @framepad = 1.0		# vertical padding for frames
    @depthmax = 0

    @white = @svg.color_allocate(255, 255, 255)
	@black = @svg.color_allocate(0, 0, 0)
	@vvdgrey = @svg.color_allocate(40, 40, 40)
	@vdgrey = @svg.color_allocate(160, 160, 160)
	@dgrey = @svg.color_allocate(200, 200, 200)

    @random = Random.new

    @timemax ||= @tree.duration

    @widthpertime = (@imagewidth - 2 * @xpad) / @timemax
    minwidth_time = @minwidth / @widthpertime

    @depthmax = @tree.depth(minwidth_time)

    @imageheight = ((@depthmax + 1) * @frameheight) + @ypad1 + @ypad2
    @imageheight += @ypad3 unless @subtitletext.empty?

  end

  attr_reader :by_language
  attr_reader :by_compilation
  attr_reader :timemax
  attr_reader :imagewidth
  attr_reader :imageheight

  def name_hash(name)
    # Generate a predictable hash for a function name, weighted towards early characters
  end

  def color_for_name(name, type=nil, use_hash=false)
    v1,= v2 = v3 = 0
    if use_hash
      v1 = name_hash(name)
      v2 = v3 = name_hash(name.reverse)
    else
      v1 = @random.rand 0.0..1.0
      v2 = @random.rand 0.0..1.0
      v3 = @random.rand 0.0..1.0
    end

    case type
    when 'hot'
      r = 205 + (50 * v3).to_i
      g = 0 + (230 * v1).to_i
      b = 0 + (55 * v2).to_i
      return @svg.color_allocate(r, g, b)
    when 'mem'
      r = 0
      g = 190 + (50 * v2).to_i
      b = 0 + (210 * v1).to_i
      return @svg.color_allocate(r, g, b)
    when 'io'
      r = 80 + (60 * v1).to_i
      g = r
      b = 190 + (55 * v2).to_i
      return @svg.color_allocate(r, g, b)
	when 'red'
	  r = 200 + (55 * v1).to_i
	  (80 * v1)
	  return @svg.color_allocate(r, x, x)
	when 'green'
	  g = 200 + (55 * v1).to_i
	  x = 50 + (60 * v1).to_i
	  return @svg.color_allocate(x, g, x)
	when 'blue'
	  b = 205 + (50 * v1).to_i
	  x = 80 + (60 * v1).to_i
	  return @svg.color_allocate(x, x, b)
	when 'yellow'
	  x = 175 + (55 * v1).to_i
	  b = 50 + (20 * v1).to_i
	  return @svg.color_allocate(x, x, b)
	when 'purple'
	  x = 190 + (65 * v1).to_i
	  g = 80 + (60 * v1).to_i
	  return @svg.color_allocate(x, g, x)
	when 'aqua'
	  r = 50 + (60 * v1).to_i
	  g = 165 + (55 * v1).to_i
	  b = 165 + (55 * v1).to_i
	  return @svg.color_allocate(r, g, b)
	when 'orange'
	  r = 190 + (65 * v1).to_i
	  g = 90 + (65 * v1).to_i
	  return @svg.color_allocate(r, g, 0)
    end

	return @svg.color_allocate(0, 0, 0)
  end

  def color_scale(value, max)
    value = -value if @negate
    r = g = b = 255
    if (value > 0)
      g = b = (210 * (max - value) / max).to_i
    else
      r = g = (210 * (max + value) / max).to_i
    end
    return @svg.color_allocate(r, g, b)
  end

  def color_map(colors, func)
    return @palette_map[func] ||= color(func, colors, @hash)
  end

  def draw_canvas
    if @tree.duration == 0
      # produce an error svg
    end

    if @timemax && @timemax < @tree.duration
      # produce an error svg
    end

    @svg.header(@imagewidth, @imageheight)

    @svg.include(generate_prelude)

    @svg.group_start(**{:id => 'flamegraph'})
    @svg.filled_rectangle(0, 0, @imagewidth, @imageheight, 'url(#background)')

    @svg.ttf_string(@black, @fonttype, @fontsize + 5, 0.0, (@imagewidth / 2).to_i, @fontsize * 2, @titletext, "middle")
    if !@subtitletext.empty?
        @svg.ttf_string(@vdgrey, @fonttype, @fontsize, 0.0, (@imagewidth / 2).to_i, @fontsize * 4, @subtitletext, "middle")
    end
    @svg.ttf_string(@black, @fonttype, @fontsize, 0.0, @xpad, @imageheight - (@ypad2 / 2), " ", "", 'id="details"')
    @svg.ttf_string(@black, @fonttype, @fontsize, 0.0, @xpad, @fontsize * 2,
                    "Reset Zoom", "", 'id="unzoom" onclick="unzoom()" style="opacity:0.0;cursor:pointer"')
    @svg.ttf_string(@black, @fonttype, @fontsize, 0.0, @imagewidth - @xpad - 100,
                    @fontsize * 2, "Search", "", 'id="search" onmouseover="searchover()" onmouseout="searchout()" onclick="search_prompt()" style="opacity:0.1;cursor:pointer"')
    @svg.ttf_string(@black, @fonttype, @fontsize, 0.0, @imagewidth - @xpad - 100, @imageheight - (@ypad2 / 2), " ", "", 'id="matched"')

    draw_tree(@tree, 0)

    @svg.group_end(id: 'flamegraph')

    @svg.close
  end

  def generate_prelude
    <<-EOF
<defs >
	<linearGradient id="background" y1="0" y2="1" x1="0" x2="0" >
		<stop stop-color="#{@bgcolor1}" offset="5%" />
		<stop stop-color="#{@bgcolor2}" offset="95%" />
	</linearGradient>
</defs>
<style type="text/css">
	.func_g:hover { stroke:black; stroke-width:0.5; cursor:pointer; }
</style>
<script type="text/ecmascript">
<![CDATA[
	var details, searchbtn, matchedtxt, svg;
	function init(evt) {
		details = document.getElementById("details").firstChild;
		searchbtn = document.getElementById("search");
		matchedtxt = document.getElementById("matched");
		svg = document.getElementsByTagName("svg")[0];
        flamegraph = document.getElementById("flamegraph");
		searching = 0;
	}

	// mouse-over for info
	function s(node) {		// show
		info = g_to_text(node);
		details.nodeValue = "#{@nametype} " + info;
	}
	function c() {			// clear
		details.nodeValue = ' ';
	}

	// ctrl-F for search
	window.addEventListener("keydown",function (e) {
		if (e.keyCode === 114 || (e.ctrlKey && e.keyCode === 70)) {
			e.preventDefault();
			search_prompt();
		}
	})

	// functions
	function find_child(parent, name, attr) {
		var children = parent.childNodes;
		for (var i=0; i<children.length;i++) {
			if (children[i].tagName == name)
				return (attr != undefined) ? children[i].attributes[attr].value : children[i];
		}
		return;
	}
	function orig_save(e, attr, val) {
		if (e.attributes["_orig_"+attr] != undefined) return;
		if (e.attributes[attr] == undefined) return;
		if (val == undefined) val = e.attributes[attr].value;
		e.setAttribute("_orig_"+attr, val);
	}
	function orig_load(e, attr) {
		if (e.attributes["_orig_"+attr] == undefined) return;
		e.attributes[attr].value = e.attributes["_orig_"+attr].value;
		e.removeAttribute("_orig_"+attr);
	}
	function g_to_text(e) {
		var text = find_child(e, "title").firstChild.nodeValue;
		return (text)
	}
	function g_to_func(e) {
		var func = g_to_text(e);
		// if there's any manipulation we want to do to the function
		// name before it's searched, do it here before returning.
		return (func);
	}
	function update_text(e) {
		var r = find_child(e, "rect");
		var t = find_child(e, "text");
		var w = parseFloat(r.attributes["width"].value) -3;
		var txt = find_child(e, "title").textContent.replace(/\\([^(]*\\)$/,"");
		t.attributes["x"].value = parseFloat(r.attributes["x"].value) +3;

		// Smaller than this size won't fit anything
		if (w < 2*#{@fontsize}*#{@fontwidth}) {
			t.textContent = "";
			return;
		}

		t.textContent = txt;
		// Fit in full text width
		if (/^ *$/.test(txt) || t.getSubStringLength(0, txt.length) < w)
			return;

		for (var x=txt.length-2; x>0; x--) {
			if (t.getSubStringLength(0, x+2) <= w) {
				t.textContent = txt.substring(0,x) + "..";
				return;
			}
		}
		t.textContent = "";
	}

	// zoom
	function zoom_reset(e) {
		if (e.attributes != undefined) {
			orig_load(e, "x");
			orig_load(e, "width");
		}
		if (e.childNodes == undefined) return;
		for(var i=0, c=e.childNodes; i<c.length; i++) {
			zoom_reset(c[i]);
		}
	}
	function zoom_child(e, x, ratio) {
		if (e.attributes != undefined) {
			if (e.attributes["x"] != undefined) {
				orig_save(e, "x");
				e.attributes["x"].value = (parseFloat(e.attributes["x"].value) - x - #{@xpad}) * ratio + #{@xpad};
				if(e.tagName == "text") e.attributes["x"].value = find_child(e.parentNode, "rect", "x") + 3;
			}
			if (e.attributes["width"] != undefined) {
				orig_save(e, "width");
				e.attributes["width"].value = parseFloat(e.attributes["width"].value) * ratio;
			}
		}

		if (e.childNodes == undefined) return;
		for(var i=0, c=e.childNodes; i<c.length; i++) {
			zoom_child(c[i], x-#{@xpad}, ratio);
		}
	}
	function zoom_parent(e) {
		if (e.attributes) {
			if (e.attributes["x"] != undefined) {
				orig_save(e, "x");
				e.attributes["x"].value = #{@xpad};
			}
			if (e.attributes["width"] != undefined) {
				orig_save(e, "width");
				e.attributes["width"].value = parseInt(svg.width.baseVal.value) - (#{@xpad}*2);
			}
		}
		if (e.childNodes == undefined) return;
		for(var i=0, c=e.childNodes; i<c.length; i++) {
			zoom_parent(c[i]);
		}
	}
	function zoom(node) {
		var attr = find_child(node, "rect").attributes;
		var width = parseFloat(attr["width"].value);
		var xmin = parseFloat(attr["x"].value);
		var xmax = parseFloat(xmin + width);
		var ymin = parseFloat(attr["y"].value);
		var ratio = (svg.width.baseVal.value - 2*#{@xpad}) / width;

		// XXX: Workaround for JavaScript float issues (fix me)
		var fudge = 0.0001;

		var unzoombtn = document.getElementById("unzoom");
		unzoombtn.style["opacity"] = "1.0";

		var el = flamegraph.getElementsByTagName("g");
		for(var i=0;i<el.length;i++){
			var e = el[i];
			var a = find_child(e, "rect").attributes;
			var ex = parseFloat(a["x"].value);
			var ew = parseFloat(a["width"].value);
			// Is it an ancestor
			if (#{@inverted ? 1 : 0} == 0) {
				var upstack = parseFloat(a["y"].value) > ymin;
			} else {
				var upstack = parseFloat(a["y"].value) < ymin;
			}
			if (upstack) {
				// Direct ancestor
				if (ex <= xmin && (ex+ew+fudge) >= xmax) {
					e.style["opacity"] = "0.5";
					zoom_parent(e);
					e.onclick = function(e){unzoom(); zoom(this);};
					update_text(e);
				}
				// not in current path
				else
					e.style["display"] = "none";
			}
			// Children maybe
			else {
				// no common path
				if (ex < xmin || ex + fudge >= xmax) {
					e.style["display"] = "none";
				}
				else {
					zoom_child(e, xmin, ratio);
					e.onclick = function(e){zoom(this);};
					update_text(e);
				}
			}
		}
	}
	function unzoom() {
		var unzoombtn = document.getElementById("unzoom");
		unzoombtn.style["opacity"] = "0.0";

		var el = flamegraph.getElementsByTagName("g");
		for(i=0;i<el.length;i++) {
			el[i].style["display"] = "block";
			el[i].style["opacity"] = "1";
			zoom_reset(el[i]);
			update_text(el[i]);
		}
	}

	// search
	function reset_search() {
		var el = flamegraph.getElementsByTagName("rect");
		for (var i=0; i < el.length; i++) {
			orig_load(el[i], "fill")
		}
	}
	function search_prompt() {
		if (!searching) {
			var term = prompt("Enter a search term (regexp " +
			    "allowed, eg: ^ext4_)", "");
			if (term != null) {
				search(term)
			}
		} else {
			reset_search();
			searching = 0;
			searchbtn.style["opacity"] = "0.1";
			searchbtn.firstChild.nodeValue = "Search"
			matchedtxt.style["opacity"] = "0.0";
			matchedtxt.firstChild.nodeValue = ""
		}
	}
	function search(term) {
		var re = new RegExp(term);
		var el = flamegraph.getElementsByTagName("g");
		var matches = new Object();
		var maxwidth = 0;
		for (var i = 0; i < el.length; i++) {
			var e = el[i];
			if (e.attributes["class"].value != "func_g")
				continue;
			var func = g_to_func(e);
			var rect = find_child(e, "rect");
			if (rect == null) {
				// the rect might be wrapped in an anchor
				// if nameattr href is being used
				if (rect = find_child(e, "a")) {
				    rect = find_child(r, "rect");
				}
			}
			if (func == null || rect == null)
				continue;

			// Save max width. Only works as we have a root frame
			var w = parseFloat(rect.attributes["width"].value);
			if (w > maxwidth)
				maxwidth = w;

			if (func.match(re)) {
				// highlight
				var x = parseFloat(rect.attributes["x"].value);
				orig_save(rect, "fill");
				rect.attributes["fill"].value =
				    "#{@searchcolor}";

				// remember matches
				if (matches[x] == undefined) {
					matches[x] = w;
				} else {
					if (w > matches[x]) {
						// overwrite with parent
						matches[x] = w;
					}
				}
				searching = 1;
			}
		}
		if (!searching)
			return;

		searchbtn.style["opacity"] = "1.0";
		searchbtn.firstChild.nodeValue = "Reset Search"

		// calculate percent matched, excluding vertical overlap
		var count = 0;
		var lastx = -1;
		var lastw = 0;
		var keys = Array();
		for (k in matches) {
			if (matches.hasOwnProperty(k))
				keys.push(k);
		}
		// sort the matched frames by their x location
		// ascending, then width descending
		keys.sort(function(a, b){
			return a - b;
		});
		// Step through frames saving only the biggest bottom-up frames
		// thanks to the sort order. This relies on the tree property
		// where children are always smaller than their parents.
		var fudge = 0.0001;	// JavaScript floating point
		for (var k in keys) {
			var x = parseFloat(keys[k]);
			var w = matches[keys[k]];
			if (x >= lastx + lastw - fudge) {
				count += w;
				lastx = x;
				lastw = w;
			}
		}
		// display matched percent
		matchedtxt.style["opacity"] = "1.0";
		pct = 100 * count / maxwidth;
		if (pct == 100)
			pct = "100"
		else
			pct = pct.toFixed(1)
		matchedtxt.firstChild.nodeValue = "Matched: " + pct + "%";
	}
	function searchover(e) {
		searchbtn.style["opacity"] = "1.0";
	}
	function searchout(e) {
		if (searching) {
			searchbtn.style["opacity"] = "1.0";
		} else {
			searchbtn.style["opacity"] = "0.1";
		}
	}
]]>
</script>
EOF
  end

  def draw_tree(tree_node, depth)

    x1 = @xpad + tree_node.offset * @widthpertime
    x2 = @xpad + (tree_node.offset + tree_node.duration) * @widthpertime

    return if (x2 - x1 < @minwidth)

    if @inverted
	  y1 = @ypad1 + depth * @frameheight
	  y2 = @ypad1 + (depth + 1) * @frameheight - @framepad
	else
	  y1 = @imageheight - @ypad2 - (depth + 1) * @frameheight + @framepad
	  y2 = @imageheight - @ypad2 - depth * @frameheight
    end

    attributes = (@nameattr[tree_node.name] ||= {})
    attributes[:class] ||= 'func_g'
    attributes[:onmouseover] ||= 's(this)'
    attributes[:onmouseout] ||= 'c()'
    attributes[:onclick] ||= 'zoom(this)'
    attributes[:title] ||= @svg.escape(tree_node.info_text(self))
    @svg.group_start(**attributes)

    color = tree_node.color(self, @colors)
    @svg.filled_rectangle(x1, y1, x2, y2, color, 'rx="2" ry="2"')

    text_length = (x2 - x1) / (@fontsize * @fontwidth)

    text = ''
    if text_length >= tree_node.name.size
      text = tree_node.name
    elsif text_length >= 3
      text = tree_node.name[0..(text_length-2)] + '..'
    end

    text = @svg.escape(text)

    @svg.ttf_string(@black, @fonttype, @fontsize, 0.0, x1 + 3, 3 + (y1 + y2) / 2, text, "")

    @svg.group_end(**attributes)

    tree_node.children.each do |t|
      draw_tree(t, depth + 1)
    end
  end
end

class TreeNode
  def initialize(children, duration, offset, name, language=nil, scale=nil)
    @children = children
    @duration = duration
    @offset = offset
    @name = name
    @language = language
    @scale = scale
  end

  attr_reader :children
  attr_reader :duration
  attr_reader :offset
  attr_reader :name
  attr_reader :language
  attr_reader :scale

  def depth(min_time=0)
    if duration < min_time
      0
    else
      1 + (children.map { |x| x.depth }.max || 0)
    end
  end

  def color(graph, default)
    if graph.by_compilation && scale
      graph.color_scale(scale, 1.0)
    elsif graph.by_language
      type = if @language
               case @language
               when 'ruby'
                 'orange'
               when 'llvm'
                 'green'
               else
                 'blue'
               end
             else
               default
             end
      graph.color_for_name(name, type)
    else
      graph.color_for_name(name, default)
    end
  end

  def info_text(graph)
    duration_str = "#{duration}".gsub(/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/, '\1,')
    total_str = "#{graph.timemax}".gsub(/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/, '\1,')
    pcnt_str = sprintf("%.2f", 100.0 * duration / graph.timemax)
    "#{name} (#{duration_str} / #{total_str} samples, #{pcnt_str}%)"
  end

end

class DataParser

  def initialize(input, source_info, timestamp_order)
    @input = input
    @source_info = source_info
    @timestamp_order = timestamp_order
    @data = JSON.load(input)
    @tool = @data.fetch("tool")
  end

  def tree
    @tree ||= parse_tree
  end

  def parse_tree
    case @tool
    when "cpusampler"
      profile = @data.fetch("profile")
      abort "Need hit times (--cpusampler.GatherHitTimes)" if @timestamp_order && !data["gathered_hit_times"]
      thread_trees = []
      offset = 0
      profile.each do |thread|
        name = thread.fetch("thread")
        samples = thread.fetch("samples")
        children, total_time = make_trees(samples, offset)
        thread_trees << TreeNode.new(children, total_time, offset, name)
        offset += total_time
      end
      TreeNode.new(thread_trees, offset, 0, "all")
    when "cputracer"
      profile = data.fetch("profile")

      profile.each do |method|
        stacks << "#{method_name(method)} #{method.fetch("count")}"
      end
    else
      abort "Unknown tool: #{tool}"
    end
  end

  def make_trees(samples, offset)
    total_time = 0
    trees = samples.map do |method|
      duration = method.fetch("hit_count")
      self_time = method.fetch("self_hit_count")
      name = method_name(method)
      source_section = method.fetch('source_section')
      language = source_section.fetch('language')
      compiled_samples = method.fetch("self_compiled_hit_count")
      interpreted_samples = method.fetch("self_interpreted_hit_count")
      scale = if self_time != 0
                (1.0 * (compiled_samples - interpreted_samples)) / self_time
              else
                0
              end
      children, child_time = make_trees(method.fetch("children"), offset + self_time)
      t = TreeNode.new(children, duration, offset, name, language, scale)
      total_time += duration
      offset += duration
      t
    end
    return trees, total_time
  end

  def method_name(method)
    name = method.fetch("root_name")
    name = name.inspect[1...-1]
    if @source_info
      source_section = method.fetch("source_section")
      source_name = source_section["source_name"]
      start_line = source_section["start_line"]
      end_line = source_section["end_line"]
      formatted_line = start_line == end_line ? start_line : "#{start_line}-#{end_line}"
      name = "#{name} #{source_name}:#{formatted_line}"
    end
    # Remove ';' as that character is reserved for collapsed stacks
    name.gsub(';', '')
  end

  def gather_samples(data)
    stack = []
    samples = []
    processing_stack = []
    current = 0
    finish = data.size
    begin
      method = data[current]
      current += 1
      stack.push method_name(method)
      method.fetch("self_hit_times").each do |time|
        samples << [stack.dup, time]
      end
      processing_stack.push([data, current, finish])
      data = data.fetch('children')
      current = 0
      fniish = data.size
      while (current >= finish)
        data, current, finish = processing_stack.pop
        return samples unless data
      end
      stack.pop
    end while true
    samples
  end

  def dump(data, stack, output)
    data.each do |method|
      stack.push method_name(method)
      output << "#{stack.join(';')} #{method.fetch("self_hit_count")}"
      dump(method.fetch("children"), stack, output)
      stack.pop
    end
  end

  def time
    @time ||= calculate_time
  end

  def calculate_time
    total_samples = 0
    case tool
    when 'cpusampler'
      profile = data.fetch("profile")
      abort "Need hit times (--cpusampler.GatherHitTimes)" if @timestamp_order && !data["gathered_hit_times"]

      profile.each do |thread|
        name = thread.fetch("thread")
        samples = thread.fetch("samples")

        samples.each do |method|
          total_samples += method.fetch("hit_count")
        end
      end
    end
    total_samples
  end

  def generate_stacks
    output = []
    case tool
    when "cpusampler"
      profile = data.fetch("profile")
      abort "Need hit times (--cpusampler.GatherHitTimes)" if @timestamp_order && !data["gathered_hit_times"]
      stack = []

      profile.each do |thread|
        name = thread.fetch("thread")
        samples = thread.fetch("samples")

        stack.push name
        if @timestamp_order
          gather_samples(samples, stack).sort_by { |stack, time| time }.each do |stack, time|
            stacks << "#{stack.join(';')} 1"
          end
        else
          dump(samples, stack)
        end
        stack.pop
      end
    when "cputracer"
      profile = data.fetch("profile")

      profile.each do |method|
        stacks << "#{method_name(method)} #{method.fetch("count")}"
      end
    else
      abort "Unknown tool: #{tool}"
    end
  end
end

# Get the stack data
data_parser = DataParser.new(ARGF, ARGV.delete('--source'), ARGV.delete('--timestamp-order'))
# Generate the canvas
svg = SVGGenerator.new
graph = FlameGraph.new(data_parser.tree, svg, by_language: ARGV.delete('--by-language'), by_compilation: ARGV.delete('--by-compilation'))
graph.draw_canvas
puts svg.output
