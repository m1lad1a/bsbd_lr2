CREATE OR REPLACE FUNCTION app.register_video_record(
    p_camera_id integer,
    p_start timestamp,
    p_end timestamp,
    p_file_path text,
    p_file_size integer,
    p_checksum varchar,
    p_storage_status varchar DEFAULT 'Активен'
)
RETURNS TABLE(success boolean, video_id integer, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id integer;
    v_success boolean := false;
    v_message text;
    v_caller name;
BEGIN
    v_caller := COALESCE(NULLIF(current_setting('role', true), 'none'), session_user::text)::name;
    video_id := NULL;

    BEGIN
        IF p_camera_id IS NULL OR p_camera_id <= 0 THEN
            RAISE EXCEPTION 'Некорректный идентификатор камеры';
        END IF;
        IF p_start IS NULL OR p_end IS NULL OR p_end <= p_start THEN
            RAISE EXCEPTION 'Время окончания должно быть позже времени начала';
        END IF;
        IF p_file_path IS NULL OR p_file_path !~ '^/storage/[A-Za-z0-9_./-]+$'
           OR p_file_path ~ '(^|/)\.\.(/|$)' THEN
            RAISE EXCEPTION 'Недопустимый путь к видеофайлу';
        END IF;
        IF p_file_size IS NULL OR p_file_size <= 0 THEN
            RAISE EXCEPTION 'Размер видеофайла должен быть положительным';
        END IF;
        IF p_checksum IS NULL OR length(btrim(p_checksum)) < 16 THEN
            RAISE EXCEPTION 'Контрольная сумма отсутствует или слишком короткая';
        END IF;
        IF p_storage_status IS NULL OR p_storage_status NOT IN ('Активен', 'В архиве') THEN
            RAISE EXCEPTION 'Недопустимый статус хранения видеозаписи';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM app."Камера" c
            WHERE c."ID_камеры" = p_camera_id AND c."Статус" = 'Работает'
        ) THEN
            RAISE EXCEPTION 'Камера не найдена или не находится в рабочем состоянии';
        END IF;

        INSERT INTO app."Видеозапись" (
            "ID_камеры", "Время_начала", "Время_окончания",
            "Путь_к_файлу", "Размер_файла", "Контрольная_сумма", "Статус_хранения"
        )
        VALUES (
            p_camera_id, p_start, p_end, p_file_path,
            p_file_size, p_checksum, p_storage_status
        )
        RETURNING "ID_видеозаписи" INTO v_id;

        v_success := true;
        v_message := 'Метаданные видеозаписи успешно зарегистрированы';
    EXCEPTION
        WHEN raise_exception THEN v_message := SQLERRM;
        WHEN unique_violation THEN v_message := 'Видеозапись с такими ключевыми данными уже существует';
        WHEN OTHERS THEN v_message := 'Ошибка регистрации видеозаписи: ' || SQLERRM;
    END;

    INSERT INTO audit.function_calls(function_name, caller_role, input_params, success, message)
    VALUES (
        'app.register_video_record', v_caller,
        jsonb_build_object(
            'camera_id', p_camera_id, 'start', p_start, 'end', p_end,
            'file_path', p_file_path, 'file_size', p_file_size,
            'checksum', p_checksum, 'storage_status', p_storage_status
        ),
        v_success, v_message
    );

    success := v_success;
    video_id := v_id;
    message := v_message;
    RETURN NEXT;
END;
$$;
