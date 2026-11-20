CREATE OR REPLACE FUNCTION app.change_camera_status(
    p_camera_id integer,
    p_new_status varchar
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_old_status varchar(20);
    v_success boolean := false;
    v_message text;
    v_caller name;
BEGIN
    v_caller := COALESCE(NULLIF(current_setting('role', true), 'none'), session_user::text)::name;

    BEGIN
        IF p_camera_id IS NULL OR p_camera_id <= 0 THEN
            RAISE EXCEPTION 'Некорректный идентификатор камеры';
        END IF;
        IF p_new_status IS NULL OR p_new_status NOT IN ('Работает', 'Не работает', 'Обслуживание') THEN
            RAISE EXCEPTION 'Недопустимый статус камеры';
        END IF;

        SELECT c."Статус" INTO v_old_status
        FROM app."Камера" c
        WHERE c."ID_камеры" = p_camera_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Камера не найдена';
        END IF;
        IF v_old_status = p_new_status THEN
            RAISE EXCEPTION 'Камера уже имеет указанный статус';
        END IF;

        UPDATE app."Камера"
        SET "Статус" = p_new_status
        WHERE "ID_камеры" = p_camera_id;

        v_success := true;
        v_message := 'Статус камеры успешно изменён';
    EXCEPTION
        WHEN raise_exception THEN v_message := SQLERRM;
        WHEN OTHERS THEN v_message := 'Ошибка изменения статуса камеры: ' || SQLERRM;
    END;

    INSERT INTO audit.function_calls(function_name, caller_role, input_params, success, message)
    VALUES (
        'app.change_camera_status', v_caller,
        jsonb_build_object('camera_id', p_camera_id, 'new_status', p_new_status),
        v_success, v_message
    );

    success := v_success;
    message := v_message;
    RETURN NEXT;
END;
$$;
