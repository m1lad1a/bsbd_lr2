CONSTRAINT ck_lab2_video_valid CHECK (
    end_time > start_time AND file_size > 0
)
