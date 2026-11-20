CREATE OR REPLACE FUNCTION app.grant_camera_access(
    p_user_id integer,
    p_camera_id integer,
    p_access_level_id integer,
    p_end_date timestamp DEFAULT NULL
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_success boolean := false;
    v_message text;
    v_caller name;
BEGIN
    v_caller := COALESCE(NULLIF(current_setting('role', true), 'none'), session_user::text)::name;

    BEGIN
        IF p_user_id IS NULL OR p_user_id <= 0
           OR p_camera_id IS NULL OR p_camera_id <= 0
           OR p_access_level_id IS NULL OR p_access_level_id <= 0 THEN
            RAISE EXCEPTION 'Идентификаторы пользователя, камеры и уровня доступа должны быть положительными';
        END IF;
        IF p_end_date IS NOT NULL AND p_end_date <= CURRENT_TIMESTAMP THEN
            RAISE EXCEPTION 'Дата окончания доступа должна быть в будущем';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM app."Пользователь_системы" u
            WHERE u."ID_пользователя" = p_user_id AND u."Активен" = true
        ) THEN
            RAISE EXCEPTION 'Пользователь не найден или заблокирован';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM app."Камера" c
            WHERE c."ID_камеры" = p_camera_id
        ) THEN
            RAISE EXCEPTION 'Камера не найдена';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM ref."Уровень_доступа" a
            WHERE a."ID_уровня_доступа" = p_access_level_id
        ) THEN
            RAISE EXCEPTION 'Уровень доступа не найден';
        END IF;

        INSERT INTO app."Доступ_к_камере"(
            "ID_пользователя", "ID_камеры", "ID_уровня_доступа",
            "Дата_предоставления", "Дата_окончания"
        )
        VALUES (p_user_id, p_camera_id, p_access_level_id, CURRENT_TIMESTAMP, p_end_date)
        ON CONFLICT ("ID_пользователя", "ID_камеры")
        DO UPDATE SET
            "ID_уровня_доступа" = EXCLUDED."ID_уровня_доступа",
            "Дата_предоставления" = CURRENT_TIMESTAMP,
            "Дата_окончания" = EXCLUDED."Дата_окончания"
        WHERE app."Доступ_к_камере"."Дата_окончания" IS NOT NULL
          AND app."Доступ_к_камере"."Дата_окончания" < CURRENT_TIMESTAMP;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Для пользователя уже существует действующее назначение доступа к этой камере';
        END IF;

        v_success := true;
        v_message := 'Доступ к камере успешно предоставлен или обновлён';
    EXCEPTION
        WHEN raise_exception THEN v_message := SQLERRM;
        WHEN unique_violation THEN v_message := 'Назначение доступа конфликтует с существующей записью';
        WHEN OTHERS THEN v_message := 'Ошибка предоставления доступа: ' || SQLERRM;
    END;

    INSERT INTO audit.function_calls(function_name, caller_role, input_params, success, message)
    VALUES (
        'app.grant_camera_access', v_caller,
        jsonb_build_object(
            'user_id', p_user_id, 'camera_id', p_camera_id,
            'access_level_id', p_access_level_id, 'end_date', p_end_date
        ),
        v_success, v_message
    );

    success := v_success;
    message := v_message;
    RETURN NEXT;
END;
$$;
