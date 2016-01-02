# encode_speedrun.rb
Simple workflow for encoding speedruns with timecode for YouTube

1.  Encode a short video of the start and end with frame numbers shown:

    ```
    ./encode_speedrun.rb --input recording.ts --frames --start START_GUESS --end END_GUESS --output frames.mp4
    ```

    (where `START_GUESS` and `END_GUESS` are rough guesses of the start and end of the speedrun in seconds)

1.  Encode the final video:

    ```
    ./encode_speedrun.rb --input recording.ts --start START_FRAME --end END_FRAME --overscan OVERSCAN --output speedrun.mp4
    ```

    (where `START_FRAME` and `END_FRAME` are the frame numbers determined by the output of step 1)

    `OVERSCAN` is optional and can be one of three values:

    * `0`: No overscan (default)
    * `5`: 5% overscan (Ocarina of Time)
    * `6.25`: 6.25% overscan (The Wind Waker)
