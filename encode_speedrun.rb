#!/usr/bin/env ruby

require 'optparse'

class EncodeSpeedrun

  POSSIBLE_OVERSCAN = %w{0 5 6.25}

  def initialize
    @input = nil
    @output = nil
    @start_frame = 0
    @end_frame = nil
    @overscan = 0
    @sample_duration = nil
    @mode = :encode

    OptionParser.new do |opts|
      opts.banner = 'Usage: encode_speedrun -i input.ts -o output.mp4 -s 300 -e 3000 [options]'

      opts.on('-i', '--input FILE', 'Input recording') do |file|
        @input = file
      end
      opts.on('-o', '--output FILE', 'Output MP4 file (ex. speedrun.mp4)') do |file|
        @output = file
      end
      opts.on('-s', '--start FRAME', Integer, 'Starting frame of speedrun (default 0), output will start here') do |start_frame|
        @start_frame = start_frame
      end
      opts.on('-e', '--end FRAME', Integer, 'Final frame of speedrun, timecode will stop here') do |end_frame|
        @end_frame = end_frame
      end
      opts.on('--overscan PERCENT', POSSIBLE_OVERSCAN, "Percentage to overscan, (default 0). Possible values: #{POSSIBLE_OVERSCAN.join(', ')}") do |percent|
        @overscan = percent.to_f / 100
      end
      opts.on('--sample DURATION', Integer, 'Limit output to DURATION seconds, useful for testing') do |duration|
        @sample_duration = duration
      end
      opts.on('--frames', 'Output a 1 minute video with frame counts to determine start and finish') do
        @mode = :frames
      end
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end.parse!

    unless @input && @output && @end_frame
      abort %q{One of input, ouput, or end was not specified. Please use "encode_speedrun -h" to see options.}
    end
  end

  def ffmpeg_cmd
    @ffmpeg_cmd ||= begin
      if @mode == :encode
        ffmpeg_encode_cmd
      elsif @mode == :frames
        ffmpeg_frames_cmd
      end
    end
  end

  def ffmpeg_encode_cmd
    cmd = ['ffmpeg']

    cmd.push %Q{-i "#{@input}"}

    vfilters = []
    vfilters.push 'fps=30'
    vfilters.push "trim=start_frame=#{@start_frame}"
    vfilters.push 'setpts=PTS-STARTPTS'
    vfilters.push 'crop=704:480,scale=640:480'
    if @overscan > 0
      vfilters.push "crop=#{overscan_width}:#{overscan_height},scale=640:480"
    end
    vfilters.push %Q{drawtext="timecode='00\\:00\\:00\\:00':r=30:#{drawtext_style}:enable='lt(n,#{total_frames})'"}
    vfilters.push %Q{drawtext="text='#{final_timecode}':#{drawtext_style}:enable='gte(n,#{total_frames})'"}
    cmd.push "-vf #{vfilters.join(',')}"

    cmd.push "-af atrim=start_sample=#{start_sample},asetpts=PTS-STARTPTS"

    cmd.push '-aspect 4:3'

    cmd.push '-c:v libx264'
    cmd.push '-crf 18'
    cmd.push '-preset veryslow'
    cmd.push '-tune film'

    # YouTube encoding settings
    cmd.push '-profile:v high'
    cmd.push '-pix_fmt +yuv420p'
    cmd.push '-bf 2'
    cmd.push '-flags +cgop'
    cmd.push '-g 15'
    cmd.push '-coder ac'
    cmd.push '-movflags +faststart'

    cmd.push '-c:a libfdk_aac'
    cmd.push '-b:a 128k'

    if @sample_duration
      cmd.push "-t #{@sample_duration}"
    end

    cmd.push '-f mp4'
    cmd.push @output

    cmd.join ' '
  end

  def ffmpeg_frames_cmd
    start_seconds = @start_frame
    start_seconds -= 15 if start_seconds > 15
    end_seconds = @end_frame
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

  def total_frames
    @total_frames ||= @end_frame - @start_frame
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

end

if __FILE__ == $0
  cmd = EncodeSpeedrun.new.ffmpeg_cmd
  puts cmd
  exec cmd
end
