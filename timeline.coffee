log = (x)-> console.log(x)

# All ranges is [from, to)

class Timeline
	constructor: (container, config = {}, data = {})->
		@$container = $ container
		@config = $.extend true, @getDefaultConfig(), config
		@data = $.extend {items:[]}, data

		@ranges = []
		@addRange range for range in @config.ranges

		@lines = []
		@addLine line for line in @config.lines

		@build()

	addRange: (range)->
		for range2 in @ranges
			if range.from < range2.to and range.to > range2.from 
				throw 'Can\'t add range overlapping existing one'

		@ranges.push range
		@ranges = @ranges.sort (a, b)->
			a.from - b.from

	addLine: (line)->
		for line2 in @lines
			if line2.name is line.name
				throw 'Can\'t add line with same name as existing one has'

		@lines.push line
		@lines = @lines.sort (a, b)->
			(a.order ? 0) - (b. order? 0)

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
			ranges:
				render: $.proxy @, 'renderFieldRange'
			items:
				render: $.proxy @, 'renderFieldItem'
		range:
			extraOffset: 
				before: 5
				after: 15
		line:
			height: 30
			extraOffset:
				before: 5
				after: 10	
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
		$range.css
			left: @getOffset(range.from) - @config.range.extraOffset.before
			width: @getRangeInnerWidth(range)

	buildRulerDashes: ->
		@$rulerDashes = @addDom 'dashes', @$ruler
		dashes = @calcRulerDashes()
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
		Math.ceil((time - range.from) / @config.scale) +
		@config.range.extraOffset.before

	getRangeOffset: (range)->
		sum = 0
		for range2 in @ranges when range2.from < range.from
			sum += @getRangeOuterWidth range2
		sum

	getRangeInnerWidth: (range)->
		Math.ceil((range.to - range.from) / @config.scale)

	getRangeOuterWidth: (range)->
		@getRangeInnerWidth(range) +
		@config.range.extraOffset.before +
		@config.range.extraOffset.after

	getRangeByTime: (time)->
		for range in @ranges
			if range.from <= time < range.to
				return range

	calcRulerDashes: ->
		dashes = []
		for rule in @config.ruler.dashes 
			for range in @ranges
				if rule.type is 'every'
					dashes = dashes.concat @calcRulerDashesEvery(range, rule)
		dashes

	calcRulerDashesEvery: (range, rule)->
		dashes = []
		time = range.from
		while time < range.to
			dashes.push {time, class: rule.class}
			time += rule.step
		dashes

	buildSidebar: ->
		@$sidebar = @addDom 'sidebar', @$root
		@buildSidebarLines()

	buildSidebarLines: ->
		@$sidebarLines = @addDom 'lines', @$sidebar
		@buildSidebarLine line for line in @lines

	buildSidebarLine: (line)->
		$line = @addDom 'line', @$sidebarLines
		render = line.sidebarRender ? @config.sidebar.lines.render
		$line.html render line
		@placeSidebarLine $line, line

	renderSidebarLine: (line)->
		@addDom('heading').text line.name

	placeSidebarLine: ($line, line)->
		$line.css
			top: @getVerticalOffset(line.name) - @config.line.extraOffset.before
			height: @getLineInnerHeight line

	getVerticalOffset: (lineName)->	
		line = @getLineByName lineName
		if line?
			@getLineVerticalOffset(line) + @config.line.extraOffset.before

	getLineVerticalOffset: (line)->
		sum = 0
		for line2 in @lines
			break if line2.name is line.name
			sum += @getLineOuterHeight line2
		sum

	getLineInnerHeight: (line)->
		line.height ? @config.line.height

	getLineOuterHeight: (line)->
		@getLineInnerHeight(line) +
		@config.line.extraOffset.before +
		@config.line.extraOffset.after

	getLineByName: (lineName)->
		for line in @lines
			if line.name is lineName
				return line

	buildField: ->
		@$field = @addDom 'field', @$root
		@buildFieldLines()
		@buildFieldRanges()
		@buildFieldItems()

	buildFieldLines: ->
		@$fieldLines = @addDom 'lines', @$field
		@buildFieldLine line for line in @lines

	buildFieldLine: (line)->
		$line = @addDom 'line', @$fieldLines
		render = line.fieldRender ? @config.field.lines.render
		$line.html render line
		@placeFieldLine $line, line

	renderFieldLine: (line)->
		''

	placeFieldLine: ($line, line)->
		$line.css
			top: @getVerticalOffset(line.name) - @config.line.extraOffset.before
			height: @getLineInnerHeight line

	buildFieldRanges: ->
		@$fieldRanges = @addDom 'ranges', @$field
		@buildFieldRange range for range in @ranges

	buildFieldRange: (range)->
		$range = @addDom 'range', @$fieldRanges
		render = range.fieldRender ? @config.field.ranges.render
		$range.html render range
		@placeFieldRange $range, range

	renderFieldRange: (range)->
		''

	placeFieldRange: ($range, range)->
		$range.css
			left: @getOffset(range.from) - @config.range.extraOffset.before
			width: @getRangeInnerWidth(range)

	buildFieldItems: ->
		@$fieldItems = @addDom 'items', @$field
		@buildFieldItem item for item in @data.items

	buildFieldItem: (item)->
		$item = @addDom 'item', @$fieldItems
		render = item.render ? @config.field.items.render
		$item.html render item

	renderFieldItem: (item)->
		item.html ? $('<p />').text(item.text)

window.Timeline = Timeline