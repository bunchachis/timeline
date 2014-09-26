log = (x)-> console.log(x)

# All ranges is [from, to)

class Timeline
	constructor: (container, config = {}, data = {})->
		@$container = $ container
		@config = $.extend true, @getDefaultConfig(), config
		@data = $.extend {lines:[], items:[]}, data

		@ranges = []
		@addRange range for range in @config.ranges

		@build()

	addRange: (range)->
		for range2 in @ranges
			throw 'Can\'t add range overlapping existing one' if range.from < range2.to and range.to > range2.from 

		@ranges.push range
		@ranges = @ranges.sort (a, b)->
			a.from - b.from

	getDefaultConfig: ->
		ruler:
			position: 'top'
			dashes: []
			ranges:
				render: $.proxy @, 'renderRulerRange'
		sidebar:
			position: 'left'
			lines:
				render: $.proxy @, 'renderSidebarLine'
		field:
			lines:
				render: $.proxy @, 'renderFieldLine'
			items:
				render: $.proxy @, 'renderFieldItem'
		ranges: []

	addDom: (name, $container)->
		element = $('<div />').addClass "tl-#{name}"
		element.appendTo $container if $container
		element

	build: ->
		@$root = @addDom 'root', @$container
		@buildSidebar()
		@buildRuler()
		@buildField();

	buildSidebar: ->
		@$sidebar = @addDom 'sidebar', @$root
		@buildSidebarLines()

	buildRuler: ->
		@$ruler = @addDom 'ruler', @$root
		@buildRulerRanges()
		@buildRulerDashes()

	buildRulerRanges: ->
		@$rulerRanges = @addDom 'ranges', @$ruler
		@buildRulerRange range for range in @ranges

	buildRulerRange: (range)->
		$range = @addDom 'range', @$rulerRanges
		render = range.rulerRender ? @config.ruler.ranges.render
		$range.html render range
		@placeRulerRange $range, range

	renderRulerRange: (range)->
		from = moment.unix(range.from).format('DD.MM.YYYY HH:mm:ss')
		to = moment.unix(range.to).format('DD.MM.YYYY HH:mm:ss')
		@addDom('heading').text "#{from} — #{to}"

	placeRulerRange: ($range, range)->
		offset = @getOffset range.from
		$range.css
			left: offset
			width: @getOffset(range.to) - offset

	buildRulerDashes: ->
		@$rulerDashes = @addDom 'dashes', @$ruler
		dashes = @calculateRulerDashes()
		@buildRulerDash dash for dash in dashes

	buildRulerDash: (dash)->
		$dash = @addDom 'dash', @$rulerDashes
		$dash.addClass dash.class if dash.class
		@placeRulerDash $dash, dash

	placeRulerDash: ($dash, dash)->
		offset = @getOffset dash.time
		if offset?
			$dash.css {left: offset}

	getOffset: (time)->	
		range = @getRangeByTime time
		if range?
			@getRangeOffset(range) + @getInRangeOffset(range, time)

	getInRangeOffset: (range, time)->
		Math.ceil((time - range.from) / @config.scale)

	getRangeOffset: (range)->
		sum = 0
		for range2 in @ranges when range2.from < range.from
			sum += @getRangeWidth range2
		sum

	getRangeWidth: (range)->
		Math.ceil((range.to - range.from) / @config.scale)

	getRangeByTime: (time)->
		for range in @ranges
			if range.from <= time <= range.to
				return range

	calculateRulerDashes: ->
		dashes = []
		for rule in @config.ruler.dashes 
			for range in @ranges
				if rule.type is 'every'
					dashes = dashes.concat @calculateRulerDashesEvery(range, rule)
		dashes

	calculateRulerDashesEvery: (range, rule)->
		dashes = []
		time = range.from
		while time < range.to
			dashes.push {time, class: rule.class}
			time += rule.step
		dashes

	buildSidebarLines: ->
		@$sidebarLines = @addDom 'lines', @$sidebar
		@buildSidebarLine line for line in @getSortedLines()

	buildSidebarLine: (line)->
		$line = @addDom 'line', @$sidebarLines
		render = line.sidebarRender ? @config.sidebar.lines.render
		$line.html render line

	renderSidebarLine: (line)->
		@addDom('heading').text line.name

	buildField: ->
		@$field = @addDom 'field', @$root
		@buildFieldLines()
		@buildFieldItems()

	buildFieldLines: ->
		@$fieldLines = @addDom 'lines', @$field
		@buildFieldLine line for line in @getSortedLines()

	buildFieldLine: (line)->
		$line = @addDom 'line', @$fieldLines
		render = line.fieldRender ? @config.field.lines.render
		$line.html render line

	renderFieldLine: (line)->
		''

	buildFieldItems: ->
		@$fieldItems = @addDom 'items', @$field
		@buildFieldItem item for item in @data.items

	buildFieldItem: (item)->
		$item = @addDom 'item', @$fieldItems
		render = item.render ? @config.field.items.render
		$item.html render item

	renderFieldItem: (item)->
		item.html ? $('<p />').text(item.text)

	getSortedLines: ->
		@data.lines.sort (a, b)->
			(a.order ? 0) - (b. order? 0)

window.Timeline = Timeline