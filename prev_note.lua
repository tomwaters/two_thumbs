-- thing 1
-- look at gap to previous note
engine.name = 'PolyPerc'

MusicUtil = require "musicutil"

options = {}
options.OUTPUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"}

local midi_out_device
local midi_out_channel

local scale_names = {}
local scale = {}            -- current scale
local scale_notes = {}      -- notes in current scale
local active_notes = {}     -- playing notes

local current_seq_like = 0  -- current sequence is liked (1) or disliked (-1)
local learnings = {}        -- state of current learnings

notes_off_metro = metro.init()

function init_learning()
  local num_notes = 4
  for i=1, num_notes do
    learnings[i] = {
      prob_rest = i==1 and 0 or 0.1,
      prob_step = {}
    }
  end
end

function init()
  math.randomseed(os.time())
  init_learning()
  
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  
  midi_out_device = midi.connect(1)
  midi_out_device.event = function() end
  
  notes_off_metro.event = all_notes_off
  
  params:add{type = "option", id = "output", name = "output",
    options = options.OUTPUT,
    action = function(value)
      all_notes_off()
      if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
    end}
  params:add{type = "number", id = "midi_out_device", name = "midi out device", min = 1, max = 4, default = 1,
    action = function(value) midi_out_device = midi.connect(value) end}
  params:add{type = "number", id = "midi_out_channel", name = "midi out channel", min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_off()
      midi_out_channel = value
    end}
  params:add_separator()
  
  params:add{type = "option", id = "note_length", name = "note length",
    options = {"25%", "50%", "75%", "100%"},
    default = 4}
  
  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() build_scale() end}
  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end}

  params:add_separator()

  cs_AMP = controlspec.new(0,1,'lin',0,0.5,'')
  params:add{type="control",id="amp",controlspec=cs_AMP,
    action=function(x) engine.amp(x) end}

  cs_PW = controlspec.new(0,100,'lin',0,50,'%')
  params:add{type="control",id="pw",controlspec=cs_PW,
    action=function(x) engine.pw(x/100) end}

  cs_REL = controlspec.new(0.1,3.2,'lin',0,1.2,'s')
  params:add{type="control",id="release",controlspec=cs_REL,
    action=function(x) engine.release(x) end}

  cs_CUT = controlspec.new(50,5000,'exp',0,800,'hz')
  params:add{type="control",id="cutoff",controlspec=cs_CUT,
    action=function(x) engine.cutoff(x) end}

  cs_GAIN = controlspec.new(0,4,'lin',0,1,'')
  params:add{type="control",id="gain",controlspec=cs_GAIN,
    action=function(x) engine.gain(x) end}
  
  cs_PAN = controlspec.new(-1,1, 'lin',0,0,'')
  params:add{type="control",id="pan",controlspec=cs_PAN,
    action=function(x) engine.pan(x) end}

  params:default()

  clock.run(step)
end


--------------------------------------------------------
-- input
--------------------------------------------------------
function like()
  if current_seq_like < 1 then
    learn(true)
    current_seq_like = current_seq_like + 1
  end
end

function dislike()
  if current_seq_like > -1 then
    learn(false)
    current_seq_like = current_seq_like - 1
  end
end

function enc(n, delta)
end

function key(n, z)
  if z == 0 then
    if n == 2 then
      like()
    elseif n == 3 then
      dislike()
    end
    redraw()
  end
end
--------------------------------------------------------

--------------------------------------------------------
-- Playing / Stopping sound
--------------------------------------------------------
function all_notes_off()
  if (params:get("output") == 2 or params:get("output") == 3) then
    for _, a in pairs(active_notes) do
      midi_out_device:note_off(a, nil, midi_out_channel)
    end
  end
  active_notes = {}
end

function play_note(note_num)
  if note_num > -1 then
    local freq = MusicUtil.note_num_to_freq(note_num)
    
    -- Audio engine out
    if params:get("output") == 1 or params:get("output") == 3 then
      engine.hz(freq)
    elseif params:get("output") == 4 then
      crow.output[1].volts = (note_num-60)/12
      crow.output[2].execute()
    elseif params:get("output") == 5 then
      crow.ii.jf.play_note((note_num-60)/12,5)
    end

    -- MIDI out
    if (params:get("output") == 2 or params:get("output") == 3) then
      midi_out_device:note_on(note_num, 96, midi_out_channel)
      table.insert(active_notes, note_num)

      -- Note off timeout
      if params:get("note_length") < 4 then
        notes_off_metro:start((60 / params:get("clock_tempo")) * params:get("note_length"), 1)
      end
    end
  end
end
--------------------------------------------------------

--------------------------------------------------------
-- draw
--------------------------------------------------------
function redraw()
  screen.clear()
  screen.aa(1)
  
  screen.level(15)
  if current_seq_like == 1 then
    screen.move(2, 63)
    screen.line(22, 63)
  elseif current_seq_like == -1 then
    screen.move(24, 63)
    screen.line(46, 63)
  end
  screen.stroke()
  
  screen.display_png(norns.state.path..'up.png', 2, 38)
  screen.display_png(norns.state.path..'down.png', 24, 38)
  
  screen.update()
end
--------------------------------------------------------


--------------------------------------------------------
-- everything else
--------------------------------------------------------

local seq_notes = {}
function build_seq()
  local new_seq_notes = {}
  new_seq_notes[1] = #scale.intervals
  for n=2, 4 do
    local r_rest = math.random()
    if r_rest < learnings[n].prob_rest then
      new_seq_notes[n] = -1
    else
      
      -- build prob table
      local prev = new_seq_notes[n-1]
      local prob_table = {}
      local total = 0
      for i=1, #scale_notes do
        local diff = n - prev
        if learnings[n].prob_step[diff] ~= nil then
          prob_table[i] = learnings[n].prob_step[diff]
        elseif i < #scale.intervals - 1 or i > #scale_notes - #scale.intervals - 1 then
          prob_table[i] = 0.25
        else
          prob_table[i] = 0.5
        end
        total = total + prob_table[i]
      end

      -- pick rand
      total = math.floor(total * 1000)
      local c = math.random(total) / 1000
      
      -- find that in prob_table
      local acc = 0
      for i=1, #prob_table do
        acc = acc + prob_table[i]
        if acc > c then
          new_seq_notes[n] = i
          break
        end
      end
    end
  end
  
  return new_seq_notes
end

function build_scale()
  -- get 3 octaves of notes in the selected scale with selected root in the middle
  scale = MusicUtil.SCALES[params:get("scale_mode")]
  local scale_length = (#scale.intervals - 1) * 3
  local oct_dn_root = params:get("root_note") - scale.intervals[#scale.intervals]
  scale_notes = MusicUtil.generate_scale_of_length(oct_dn_root, params:get("scale_mode"), scale_length)
  seq_notes = build_seq()
end

local bar_beat = 1
function step()
  clock.sync(3)
  while true do
    clock.sync(1)
    all_notes_off()

    local x = seq_notes[bar_beat]
    if x > -1 then
      local note_num = scale_notes[x]
      play_note(note_num)
    end
    
    redraw()
    
    -- beat counter - 4 beat rest after 4 beats
    bar_beat = bar_beat + 1
    if bar_beat > 4 then
      local next_seq_notes = build_seq()
      bar_beat = 1
      
      clock.sync(4)
      
      current_seq_like = 0
      seq_notes = next_seq_notes
    end

  end
end

-- analyse the current sequence and adjust probabilities
function learn(like)
  debug_print("learning: "..(like and 'like' or 'dislike'))
  
  local alt = like and 1 or -1
  local inc = 0.1
  local clamp_min = 0.05
  local clamp_max = 0.95
  
  for n=1, #seq_notes do
    debug_print("learning note "..n)
    
    -- change chance of a rest
    if seq_notes[n] == -1 then
      local a = like and 1 or -1
      local p_rest = util.clamp(learnings[n].prob_rest + (a * inc), clamp_min, clamp_max)
      learnings[n].prob_rest = p_rest
    end
    
    -- compare note to previous
    if n > 1 and seq_notes[n] > -1 then
      local d = seq_notes[n] - seq_notes[n - 1]
      if learnings[n].prob_step[d] == nil then
        learnings[n].prob_step[d] = 0.5 
      end
      print(learnings[n].prob_step[d])
      learnings[n].prob_step[d] = util.clamp(learnings[n].prob_step[d] + (alt * inc), clamp_min, clamp_max)
      print(learnings[n].prob_step[d])
    end
    
  end
end

--------------------------------------------------------

function debug_print(msg)
  if true then
    print(msg)
  end
end

function stop()
  all_notes_off()
end


function cleanup()
end