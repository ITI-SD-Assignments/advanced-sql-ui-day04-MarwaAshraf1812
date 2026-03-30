-- Q1 Use COALESCE to display each student's nationality. If nationality is NULL, show 'Unknown'.

select * from students;
select nationality , coalesce (nationality , 'unknown') as s_nationality from students;

-- Q2 Use NULLIF to treat a GPA of 0.0 as NULL. Show student name, their real GPA, and a cleaned
-- version where 0.0 becomes NULL.

select first_name, gpa as real_gpa, nullif(gpa , 0) as cleaned_gpa 
from students;


-- Q3 Combine COALESCE + NULLIF: show each student's GPA. If GPA is NULL or 0.0, display 'Not
-- Evaluated'.
select nationality , coalesce(nullif(nationality, ' ') , 'unknown') as s_nationality from students;

-- Bonus Use NULLIF to calculate average GPA per department, avoiding division by zero. Use
-- COALESCE to replace NULL results with 0. Show dept_name, student count, and safe average GPA.
select dept_name,
count (student_id) as total_students,
coalesce(sum(gpa) / nullif(count(student_id), 0), 0) as avg_gpa
from departments d
left join students s on d.dept_id = s.dept_id
group by dept_name;

-- Q4 Create a temporary table temp_course_stats with: course_code, course_name,
-- enrolled_count, avg_grade. Then find courses where avg_grade is above 75
create temp table temp_course_stats as
select c.course_code , c.course_name, count(e.enrolled_at) as enrolled_count, avg(e.grade) as avg_grade
from courses c
join enrollments e on c.course_id = e.course_id
group by c.course_name , c.course_code;

select * from temp_course_stats where avg_grade > 75;

-- Q5 Create a B-tree index on dept_id in the students table.
create index idx_students_dept_id on students(dept_id);


-- Q6 Create a UNIQUE index on the email column of students. Then try to insert a duplicate email and observe the error.
create unique index idx_students_email on students(email);

-- Q7 Create a Partial index on salary in professors — only for active professors (is_active = TRUE
create index idx_active_prof_salary on professors(salary) where is_active = true;

select * from professors;

-- Q8 Create a view called v_student_details showing: student_id, full_name, email, gpa, dept_name,
-- faculty_name. Query it to list students in dept_id = 3.
create view v_student_details as
select s.student_id,
concat(s.first_name, ' ', s.last_name) as full_name, s.email, s.gpa, d.dept_name, f.faculty_name, d.dept_id
from students s
join  departments d on s.dept_id = d.dept_id
join faculties f on f.faculty_id = d.faculty_id;

select * from v_student_details where dept_id = 3;

-- Q9 Create an audit table enrollment_audit. Then create a BEFORE UPDATE trigger on
-- enrollments: if the grade changed, log old_grade, new_grade, student_id, changed_at, changed_by
-- into the audit table.
create table enrollment_audit(
	audit_id SERIAL PRIMARY KEY,
    student_id INTEGER,
    old_grade NUMERIC,
    new_grade NUMERIC,
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    changed_by TEXT DEFAULT CURRENT_USER
)

create or replace function log_grade_changes()
returns trigger as 
$$
begin
if (new.grade is distinct from old.grade) then
insert into enrollment_audit(student_id, old_grade, new_grade)
values(old.student_id, old.grade, new.grade);
end if;
return new;
end;
$$ language plpgsql;

create trigger trg_enrollment_grade
before update on enrollments
for each row
execute function log_grade_changes();

-- drop trigger if exists trg_enrollment_grade on enrollments cascade;


-- Q10 Test the grade trigger: update the grade of enrollment_id = 1.
--Verify the audit log was written. Then update again with the SAME grade
-- and confirm no new audit row.

select * from enrollments;

update enrollments set grade = 98 where student_id = 1;

select * from enrollment_audit;


-- Q11 Create a BEFORE INSERT trigger on professors: if salary is NULL or
-- below 5000, set it to 5000 automatically.
create or replace function log_salary()
returns trigger as $$
begin 
if (new.salary is null or new.salary < 5000) then
new.salary = 5000;
end if;
return new;
end;
$$ language plpgsql;


create trigger trg_salary
before insert on  professors
for each row
execute function log_salary() ; 

-- Q12 Run a transaction that: (1) increases all professor salaries
-- in dept_id=1 by 10%, (2) inserts a log record into a salary_log table.
-- Verify both changes then COMMIT.

CREATE TABLE IF NOT EXISTS salary_log (
log_id SERIAL PRIMARY KEY,
prof_id INTEGER,
old_salary NUMERIC,
new_salary NUMERIC,
changed_by TEXT DEFAULT CURRENT_USER,
changed_at TIMESTAMPTZ DEFAULT NOW()
);

begin;
update professors
set salary = salary * 1.10
where dept_id = 1;

insert into salary_log(prof_id, old_salary, new_salary)
select prof_id, salary / 1.10, salary 
from professors 
where dept_id = 1;

select * from professors where dept_id = 1;
select * from salary_log;

commit;

ROLLBACK;


-- Q13 Demonstrate ROLLBACK: delete all enrollments for student_id=1 inside a
--transaction, then ROLLBACK. Confirm the rows are still there.
begin;
delete from enrollments where student_id=3;
select * from enrollments where student_id = 3;

rollback;
select * from enrollments where student_id = 3;

-- Q14 Use SAVEPOINTs: in one transaction, increase faculty_id=1 budget by 500,000 (save
-- SAVEPOINT), then increase faculty_id=2 budget by 500,000. Undo ONLY the second update using
-- ROLLBACK TO SAVEPOINT, then COMMIT.

begin;
update faculties
set budget = budget + 500000
where faculty_id = 1;

savepoint after_first_update;

update faculties
set budget = budget + 500000
where faculty_id = 2;

savepoint after_sec_update;

rollback to savepoint after_first_update;
commit;

-- Q15 Test SET ROLE: as registrar_user (readwrite), switch to uni_readonly only.
-- Try a SELECT (should work) and an INSERT (should fail). Then RESET ROLE.


create role uni_readonly;

grant select on all tables in schema public to uni_readonly ;

set role uni_readonly;

select * from students;

insert into students(first_name, email) VALUES ('Test', 'test@uni.edu');

reset role;


-- Q16 Revoke DELETE on the students table from uni_readwrite.
-- Verify the privilege is gone. Then revoke ALL privileges and
-- remove student_portal from uni_readonly.
create role uni_readwrite;

grant select , insert, delete, update  on all tables in schema public to uni_readwrite ;


revoke delete on student_portal from uni_readwrite;

select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'students' and grantee = 'uni_readwrite';

revoke all privileges on students from uni_readonly;

reset role;

