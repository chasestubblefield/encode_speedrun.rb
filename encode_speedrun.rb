#!/usr/bin/env ruby

require 'optparse'

class EncodeSpeedrun

  def initialize(input, options={})
    @input = input
    @output = options[:output] || 'speedrun.mp4'
    if options[:timecode]
      @timecode = true
      @start_frame, @finish_frame = options[:timecode]
    elsif options[:start_frame]
      @timecode = false
      @start_frame = options[:start_frame]
    end
    @overscan = options[:overscan] || 0
    @sample = options[:sample]
  end

  def ffmpeg_encode_cmd
    cmd = ['ffmpeg']

    cmd.push %Q{-i "#{@input}"}

    vfilters = []
    vfilters.push 'fps=30'
    if @start_frame
      vfilters.push "trim=start_frame=#{@start_frame}"
      vfilters.push 'setpts=PTS-STARTPTS'
    end
    vfilters.push 'crop=704:480,scale=640:480'
    if @overscan > 0
      vfilters.push "crop=#{overscan_width}:#{overscan_height},scale=640:480"
    end
    if @timecode
      vfilters.push %Q{drawtext="timecode='00\\:00\\:00\\:00':r=30:#{drawtext_style}:enable='lt(n,#{total_frames})'"}
      vfilters.push %Q{drawtext="text='#{final_timecode}':#{drawtext_style}:enable='gte(n,#{total_frames})'"}
    end
    cmd.push "-vf #{vfilters.join(',')}"

    if @start_frame
      cmd.push "-af atrim=start_sample=#{start_sample},asetpts=PTS-STARTPTS"
    end

    cmd.push '-aspect 4:3'

    cmd.push '-c:v libx264'
    cmd.push '-crf 14'
    cmd.push '-preset veryslow'
    cmd.push '-tune animation'

    # YouTube encoding settings
    cmd.push '-profile:v high'
    cmd.push '-pix_fmt +yuv420p'
    cmd.push '-bf 2'
    cmd.push '-flags +cgop'
    cmd.push '-g 15'
    cmd.push '-coder ac'
    cmd.push '-movflags +faststart+rtphint'

    cmd.push '-c:a aac'
    cmd.push '-b:a 256k'

    if @sample
      cmd.push "-t #{@sample}"
    end

    cmd.push '-f mp4'
    cmd.push @output

    cmd.join ' '
  end

  def total_frames
    @total_frames ||= @finish_frame - @start_frame
  end

  def start_sample
    @start_sample ||= @start_frame * 1600
  end

  def final_timecode
    @final_timecode ||= begin
      seconds, frames = total_frames.divmod(30)
      minutes, seconds = seconds.divmod(60)
      hours, minutes = minutes.divmod(60)

      [hours, minutes, seconds, frames].map { |n|
        n.to_s.rjust(2, '0')
      }.join('\:')
    end
  end

  def overscan_width
    (640 * (1 - @overscan)).to_i
  end

  def overscan_height
    (480 * (1 - @overscan)).to_i
  end

  def drawtext_style
    'x=(w-tw)/2:y=h-(2*lh):fontfile=/System/Library/Fonts/Menlo.ttc:fontsize=24:fontcolor=white:borderw=1'
  end

  def ffmpeg_frames_cmd
    start_seconds = @start
    if start_seconds <= 15
      start_seconds = 0
    else
      start_seconds -= 15
    end
    end_seconds = @finish
    end_seconds -= 15 if end_seconds > 15

    cmd = ['ffmpeg']

    cmd.push %Q{-i "#{@input}"}

    common_filter = "fps=30,drawtext=text='%{n}':#{drawtext_style}"
    start_trim = "trim=start=#{start_seconds}:duration=30,setpts=PTS-STARTPTS"
    end_trim = "trim=start=#{end_seconds}:duration=30,setpts=PTS-STARTPTS"

    cmd.push %Q{-filter_complex "[0:v]#{common_filter},#{start_trim}[a];[0:v]#{common_filter},#{end_trim}[b];[a][b]concat[out]"}
    cmd.push '-map [out]'

    cmd.push '-c:v libx264'
    cmd.push '-preset ultrafast'

    cmd.push '-f mp4'
    cmd.push @output

    cmd.join ' '
  end

end

if __FILE__ == $0
  options = {}
  possible_overscan = %w{0 5 6.25}

  OptionParser.new do |opts|
    opts.banner = 'Usage: encode_speedrun -i input.ts -o output.mp4 -s 300 -e 3000 [options]'

    opts.on('-i', '--input FILE', 'Input recording') do |file|
      options[:input] = file
    end
    opts.on('-o', '--output FILE', 'Output MP4 file (ex. speedrun.mp4)') do |file|
      options[:output] = file
    end
    opts.on('--timecode TIMECODE') do |timecode|
      options[:timecode] = timecode.split(':').map(&:to_i)
    end
    opts.on('--start_frame START_FRAME', Integer) do |start_frame|
      options[:start_frame] = start_frame
    end
    opts.on('--overscan PERCENT', possible_overscan, "Percentage to overscan, (default 0). Possible values: #{possible_overscan.join(', ')}") do |percent|
      options[:overscan] = percent.to_f / 100
    end
    opts.on('--sample DURATION', Integer, 'Limit output to DURATION seconds, useful for testing') do |duration|
      options[:sample] = duration
    end
    opts.on('--frames', 'Output a 1 minute video with frame counts to determine exact start and finish') do
      options[:frames_only] = true
    end
    opts.on('--[no-]exec', 'Execute the ffmpeg command, or just print it') do |ex|
      options[:exec] = ex
    end
    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end
  end.parse!

  unless options.has_key?(:input)
    abort %Q{Input file not specified. Please use "encode_speedrun -h" to see options.}
  end

  e = EncodeSpeedrun.new(options[:input], options)
  if options[:frames_only]
    cmd = e.ffmpeg_frames_cmd
  else
    cmd = e.ffmpeg_encode_cmd
  end
  puts cmd
  exec cmd if options[:exec]
end
