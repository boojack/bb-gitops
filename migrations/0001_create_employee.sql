-- migrations/0001_create_employee.sql
CREATE TYPE gender AS ENUM ('M', 'F', 'X');

CREATE TABLE employee (
    emp_no      SERIAL PRIMARY KEY,
    birth_date  DATE        NOT NULL,
    first_name  TEXT        NOT NULL,
    last_name   TEXT        NOT NULL,
    gender      gender      NOT NULL,
    hire_date   DATE        NOT NULL,
    email       TEXT        UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_employee_last_name ON employee (last_name);
CREATE INDEX idx_employee_hire_date ON employee (hire_date);
