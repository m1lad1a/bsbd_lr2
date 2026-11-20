IF NEW.end_time <= NEW.start_time OR NEW.file_size <= 0 THEN
    RAISE EXCEPTION 'Некорректные метаданные видеозаписи'
        USING ERRCODE = '23514';
END IF;
