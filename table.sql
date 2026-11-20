CREATE TABLE audit.function_calls (
    call_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    call_time timestamptz NOT NULL DEFAULT clock_timestamp(),
    function_name text NOT NULL,
    caller_role name NOT NULL,
    input_params jsonb NOT NULL,
    success boolean NOT NULL,
    message text
);
