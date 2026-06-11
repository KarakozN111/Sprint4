--2. Создать `dim_region`, `dim_department`, `dim_school`, `dim_group`, `dim_student`, `dim_subject`.
create schema if not exists dwh;

-- 1 регионы
drop table if exists dwh.dim_region cascade;
create table dwh.dim_region as
select distinct region_id, region_name, region_code
from raw.regions
where region_id is not null;

-- 2 департаменты
drop table if exists dwh.dim_department cascade;
create table dwh.dim_department as
select distinct department_id, region_id, department_name
from raw.departments
where department_id is not null;

-- 3 школы удаление дубликатов и изменение типа школ
drop table if exists dwh.dim_school cascade;
create table dwh.dim_school as
with grouped_schools as (
    select
        -- берем один главный id для всех записей с одинаковым бином
        min(s.school_id) as school_id,
        s.bin,
        max(s.school_name) as school_name,
        max(s.department_id) as department_id,
        max(s.locality_type) as locality_type,
        max(s.education_lang) as education_lang, 
        case
            when max(s.school_name) like '%мектеп-гимназия%' then 'gymnasium'
            when max(s.school_name) like '%гимназия%' then 'gymnasium'
            when max(s.school_name) like '%мектеп-лицей%' then 'lyceum'
            when max(s.school_name) like '%лицей%' then 'lyceum'
            when max(s.school_name) like '%орта мектеп%' then 'regular'
            when max(s.school_name) like '%жалпы білім беретін мектеп%' then 'regular'
            else max(s.school_type)
        end as school_type,
        bool_or(s.is_active) as is_active
    from raw.schools s
    where s.school_id is not null and s.bin is not null
    group by s.bin
)
select
    gs.school_id,
    gs.school_name,
    gs.bin,
    gs.locality_type,
    gs.school_type,
    gs.education_lang,
    gs.is_active,
    d.department_id,
    d.department_name,
    r.region_id,
    r.region_name
from grouped_schools gs
left join raw.departments d on d.department_id = gs.department_id
left join raw.regions r on r.region_id = d.region_id;
 
-- 6 таблица по предметам
drop table if exists dwh.dim_subject cascade;
create table dwh.dim_subject as
select distinct subject_id, subject_name, subject_group
from raw.subjects
where subject_id is not null;

--5 студенты
drop table if exists dwh.dim_student cascade;
create table dwh.dim_student as
with analyzed_students as (
    select
        st.student_id,
        st.iin,
        st.full_name,
        st.gender,
        st.birth_date,
        st.group_id,
        st.school_id,
        st.enrolled_at,
        st.is_active,
        split_part(st.full_name, ' ', 1) as current_lastname
    from raw.students st
)
select distinct
    as_st.student_id,
    as_st.iin,
    case
        when as_st.gender = 'F'
             and as_st.current_lastname not in ('ким', 'ли', 'Ким', 'Ли')
             and as_st.current_lastname not like '%а'
             and position(' ' in as_st.full_name) > 0
        then concat(
                 as_st.current_lastname,
                 'а',
                 substring(as_st.full_name from position(' ' in as_st.full_name))
             )
        else as_st.full_name
    end as full_name,
    as_st.gender,
    as_st.birth_date,
    as_st.group_id,
    coalesce(map.school_id, as_st.school_id) as school_id,
    as_st.enrolled_at,
    as_st.is_active,
    case
        when substring(as_st.iin from 1 for 6) = to_char(as_st.birth_date, 'yymmdd') then true
        else false
    end as is_valid_iin
from analyzed_students as_st
--находим параметры школы в raw
left join raw.schools s on s.school_id = as_st.school_id
-- и стыкуем с dim_school по тем же полям по которым была группировка
left join dwh.dim_school map on map.school_name = s.school_name
                            and map.department_id = s.department_id
                            and map.education_lang = s.education_lang
where as_st.student_id is not null;

--  4 группы (с привязкой к чистым id школ)
drop table if exists dwh.dim_group cascade;
create table dwh.dim_group as
select distinct
    g.group_id,
    coalesce(map.school_id, g.school_id) as school_id,
    g.grade,
    g.letter,
    g.edu_year,
    g.shift,
    g.is_active
from raw.groups g
left join raw.schools s on s.school_id = g.school_id
left join dwh.dim_school map on map.school_name = s.school_name
                            and map.department_id = s.department_id
                            and map.education_lang = s.education_lang
where g.group_id is not null;

-- fact_marks
drop table if exists dwh.fact_marks cascade;
create table dwh.fact_marks as
select distinct
    m.mark_id,
    m.student_id,
    m.subject_id,
    st.school_id,
    st.group_id,
    m.period_id,     
    m.mark_type,     
    m.mark,          
    m.mark_max,     
    m.mark_date::date as mark_date
from raw.student_marks m
join dwh.dim_student st on m.student_id = st.student_id
where m.mark_id is not null;

-- fact_attendance
drop table if exists dwh.fact_attendance cascade;
create table dwh.fact_attendance as
select distinct
    a.attendance_id,
    a.student_id,
    a.subject_id,
    st.school_id,
    st.group_id,
    a.attendance_date::date as attendance_date,

    case
        when trim(lower(a.status)) = 'late' and coalesce(a.minutes_late, 0) = 0 then 'present'
        else trim(lower(a.status))
    end as status,

    a.minutes_late
from raw.student_attendance a
join dwh.dim_student st on a.student_id = st.student_id
where a.attendance_id is not null;

-- Витрина: качество знаний и успеваемость
drop table if exists mart.mart_quality_of_knowledge cascade;
create table mart.mart_quality_of_knowledge as
with quarterly_marks as (
    --Отбираем только итоговые оценки (четвертные/полугодовые)
    select
        student_id,
        school_id,
        group_id,
        subject_id,
        period_id,
        mark
    from dwh.fact_marks
    where mark_type in ('SUMMATIVE', 'QUARTERLY') -- фильтр на итоговые оценки
),
student_subject_status as (
    --Разделяем логику на качество (4, 5) и успеваемость (3, 4, 5)
    select
        qm.*,
        --Флаг для качества знаний (только хорошисты и отличники)
        case
            when qm.mark >= 4 then 1
            else 0
        end as is_quality_mark,
        -- Флаг для успеваемости (троечники тоже)
        case
            when qm.mark >= 3 then 1
            else 0
        end as is_passing_mark
    from quarterly_marks qm
),
aggregated_data as (
    --Считаем агрегаты на уровне школы, класса и предмета
    select
        school_id,
        group_id,
        subject_id,
        period_id,
        --Сколько всего оценок выставлено по предмету
        count(student_id) as total_marks_count,
        --Сколько из них четверток и пятерок (качество)
        sum(is_quality_mark) as quality_marks_count,
        --Сколько из них троек, четверок и пятерок (успеваемость)
        sum(is_passing_mark) as passing_marks_count
    from student_subject_status
    group by school_id, group_id, subject_id, period_id
)
--Обогащаем витрину понятными названиями из справочников
select
    -- География и административная привязка
    sch.region_id,
    sch.region_name,
    sch.department_id,
    sch.department_name,

    -- Школа и класс
    sch.school_id,
    sch.school_name,
    g.group_id,
    concat(g.grade, ' ', g.letter) as class_name, 

    -- Предмет и период
    sub.subject_id,
    sub.subject_name,
    ad.period_id as quarter_number, -- номер четверти

    -- Метрики количества учеников
    ad.total_marks_count as total_graded_students,
    ad.quality_marks_count as quality_students_count,
    ad.passing_marks_count as passing_students_count, -- количество успевающих (3, 4, 5)

    -- Расчет процента качества знаний (округляем до 2 знаков, только 4 и 5)
    case
        when ad.total_marks_count > 0
        then round((ad.quality_marks_count::numeric / ad.total_marks_count::numeric) * 100, 2)
        else 0
    end as quality_of_knowledge_pct,

    -- Расчет процента успеваемости (округляем до 2 знаков, включая троечников 3, 4, 5)
    case
        when ad.total_marks_count > 0
        then round((ad.passing_marks_count::numeric / ad.total_marks_count::numeric) * 100, 2)
        else 0
    end as passing_rate_pct

from aggregated_data ad
join dwh.dim_school sch on ad.school_id = sch.school_id
join dwh.dim_group g on ad.group_id = g.group_id
join dwh.dim_subject sub on ad.subject_id = sub.subject_id;