# Sprint 1 — SQL, домен и простая аналитика

## Цель
Разобраться с данными образовательного домена и научиться получать базовые срезы.

**Основной стек технологий:** PostgreSQL /DML, DataGrip, Docker.

---

## 🗺️ Структура базы данных
Анализ проводился на основе реляционной базы данных со схемой `raw`. 
Данные связаны по алфавитному порядку и по возрастанию.

---

## Ключевые этапы и SQL-запросы

### Задания 1–3: извлечение и сортировка базовых данных
Были написаны запросы для вывода базовой информации по школам, регионам и ученикам с применением многоуровневой сортировки  для упорядочивания текста по алфавиту.
```sql
-- 3 построить список школ по регионам и районам
select raw.regions.region_name as регион,
       raw.departments.department_name as район_отдел_образования,
       raw.schools.school_id as id_школы,
       raw.schools.school_name as название_школы,
       -- дополнительно
       raw.schools.school_type as тип_школы,
       raw.schools.locality_type as тип_местности,
       raw.schools.education_lang as язык_обучения
from raw.schools

join raw.departments on raw.schools.department_id = raw.departments.department_id
join raw.regions on raw.departments.region_id = raw.regions.region_id
order by raw.regions.region_name, raw.departments.department_name, raw.schools.school_name;
```



### Задание 4: Подсчет количества учеников по регионам, школам и классам
Для реализации задачи была использована группировка `GROUP BY` и конкатенация строк (`||`) для красивого объединения параллели (`grade`) и буквы класса (`letter`).
```sql
select raw.regions.region_name as регион,
       raw.schools.school_name as название_школы,
       -- склеиваем цифру и букву класса
       raw.groups.grade || ' ' || raw.groups.letter as класс,
       count (raw.students.student_id) as количество_учеников
from raw.students

join raw.groups on raw.students.group_id= raw.groups.group_id
join raw.schools on raw.students.school_id= raw.schools.school_id
join raw.departments on raw.schools.department_id= raw.departments.department_id
join raw.regions on raw.departments.region_id=raw.regions.region_id

group by raw.regions.region_name, raw.schools.school_name, raw.groups.grade, raw.groups.letter

order by raw.regions.region_name, raw.schools.school_name, raw.groups.grade, raw.groups.letter;

```
### Задание 5: расчет среднего балла успеваемости
Запрос агрегирует оценки учеников по предметам и учебным заведениям, используя математическую функцию avg() и округление результатов до сотых через round().

```sql
select raw.subjects.subject_name as предмет,
       raw.regions.region_name as регион,
       raw.schools.school_name as название_школы,
       round(avg(raw.student_marks.mark), 2) as средний_балл
from raw.student_marks

join raw.students on student_marks.student_id= raw.students.student_id
join raw.groups on raw.students.group_id= raw.groups.group_id
join raw.schools on raw.groups.school_id=raw.schools.school_id
join raw.departments on raw.schools.department_id= raw.departments.department_id
join raw.regions on raw.departments.region_id=raw.regions.region_id
join raw.subjects on raw.student_marks.subject_id= raw.subjects.subject_id

group by raw.subjects.subject_name, raw.regions.region_name, raw.schools.school_name

order by raw.subjects.subject_name, raw.regions.region_name, raw.schools.school_name;
```

### Задание 6: найденные проблемы в данных

### 1. Дублирование ID школ
* **Локация:** таблица `school_name_aliases`
* **Описание:** присвоение абсолютно идентичных текстовых названий школ разным идентификаторам `school_id`.
* **Влияние на витрину:** Приводит к дублированию строк и эффекту "раздувания" при выполнении операции `JOIN`. Искусственно завышает количество учеников в классах и полностью искажает итоговую аналитику по конкретным школам.

Процент ошибок в датасете: 33.33%
Дубликатов: 12

```sql
with school_checks as (
    select 
        school_name_raw,
        -- считаем, сколько уникальных id привязано к этому названию
        count(distinct school_id) as id_count
    from raw.school_name_aliases
    group by school_name_raw
)
select
    -- 1. всего уникальных названий школ в таблице
    count(*) as total_unique_names,
    
    -- 2. сколько названий имеют конфликт (оно имя — разные id)
    count(case when id_count > 1 then 1 end) as names_with_duplicate_id,
    
    -- 3. процент таких ошибок от общего числа названий
    round(
        count(case when id_count > 1 then 1 end) * 100.0 / count(*), 
    2) as error_percentage
from school_checks;
```


### 2. Выход результатов за рамки допустимого диапазона
* **Локация:** таблица `exam_results` 
* **Описание:** Фиксация значений успеваемости, превышающих максимально возможный лимит (`Score (105) > Max Score (100)`).
* **Влияние на витрину:** Тяжелая математическая ошибка, искажающая метрики успеваемости и качества знаний. Агрегатные функции (например, `AVG()`) выдают результат выше 100%, что физически невозможно и полностью подрывает доверие пользователей к витрине.

Процент ошибок: 0.22%
Строк с ошибками: 8

```sql
select
    -- 1. всего студентов (строк) в таблице
    count(*) as total_students,

    -- 2. сколько студентов получили оценку выше 100
    count(case when score > 100 then 1 end) as invalid_scores_count,

    -- 3. процент таких ошибочных строк
    round(
        count(case when score > 100 then 1 end) * 100.0 / count(*),
    2) as error_percentage
from raw.exam_results;
```

### 3. Логическое противоречие классификации
* **Локация:** таблица `schools`
* **Описание:** несоответствие между реальным наименованием учреждения и его техническим типом в базе данных (например, общеобразовательные школы или гимназии классифицированы как `lyceum` и наоборот).
* **Влияние на витрину:** Полностью ломает аналитические выборки, сегментацию и работу фильтров по типам заведений. Делает невозможным точный расчет KPI в разрезе категорий школ для ведомственных отчетов.

Процент ошибок в датасете: 48.15%
Несовпадений: 13

```sql

select
    -- 1. всего строк в таблице
    count(*) as total_schools,

    -- 2. считаем строки с логическим противоречием в типах
    count(case when
        (school_name like '%жалпы білім беретін мектеп%' and school_type != 'regular') or
        (school_name like '%мектеп-гимназия%' and school_type != 'gymnasium') or
        (school_name like '%орта мектеп%' and school_type != 'regular') or
        (school_name like '%мектеп-лицей%' and school_type != 'lyceum')
    then 1 end) as type_mismatch_count,

    -- 3. итоговый процент ошибок несовпадения типов
    round(
        count(case when
            (school_name like '%жалпы білім беретін мектеп%' and school_type != 'regular') or
            (school_name like '%мектеп-гимназия%' and school_type != 'gymnasium') or
            (school_name like '%орта мектеп%' and school_type != 'regular') or
            (school_name like '%мектеп-лицей%' and school_type != 'lyceum')
        then 1 end) * 100.0 / count(*),
    2) as error_percentage

from raw.schools;
```

### 4. Логические пропуски в метриках посещаемости
* **Локация:** Таблица `student_attendance` (столбцы `late` и `minutes`)
* **Описание:** Простановка пустых значений (0) в поле минут при официально подтвержденном и зафиксированном факте опоздания ученика.
* **Влияние на витрину:** Ломает математическое агрегирование числовых метрик. Функции `SUM()` и `AVG()` игнорируют такие записи, из-за чего итоговые витрины искусственно занижают общее и среднее время опозданий учащихся, скрывая реальный масштаб нарушений.


Процент ошибки в датасете: 50,1:
Строк с ошибками: 14745

```sql
select
    -- 1. сколько всего фактов опозданий (строк со статусом LATE)
    count(case when status = 'LATE' then 1 end) as total_late_cases,

    -- 2. сколько из них с ошибкой (минуты равны 0 или пустые)
    count(case when status = 'LATE' and (minutes_late = 0 or minutes_late is null) then 1 end) as late_without_minutes,

    -- 3. процент ошибок от общего количества опозданий
    round(
        count(case when status = 'LATE' and (minutes_late = 0 or minutes_late is null) then 1 end) * 100.0
        / nullif(count(case when status = 'LATE' then 1 end), 0),
    2) as error_percentage

from raw.student_attendance;
```

### 5. Невалидные идентификаторы граждан (ИИН)
* **Локация:** таблица `students`
* **Описание:** несоответствие первые 6 цифр ИИН реальной дате рождения студентов, что нарушает алгоритм формирования идентификаторов Республики Казахстан.
* **Влияние на витрину:** полностью блокирует возможность сквозной интеграции, дедупликации и связывания витрины с любыми внешними государственными информационными системами.

Процент ошибки в датасете: 100%
```sql
select
    -- 1. всего студентов в таблице
    count(*) as total_students,

    -- 2. считаем строки, где первые 6 цифр иин НЕ совпадают с датой рождения
    count(case when left(iin::text, 6) != to_char(birth_date, 'yymmdd') then 1 end) as invalid_iin_count,

    -- 3. итоговый процент студентов с некорректными иин
    round(
        count(case when left(iin::text, 6) != to_char(birth_date, 'yymmdd') then 1 end) * 100.0
        / count(*),
    2) as error_percentage

from raw.students;
```

### 8. Гендерно-грамматические ошибки в фамилиях
* **Локация:** таблицы `students` и `teachers`
* **Описание:** смешивание мужских и женских фамилий, имен и отчеств в рамках одной записи в процессе генерации/ввода данных (например, мужская фамилия при женском имени).
* **Влияние на витрину:** напрямую на математические расчеты не влияет, но делает невозможной автоматическую генерацию документов, выгрузку персонализированных отчетов, справок и бланков, так как система выдает грамматически некорректные и невалидные данные.

Процент ошибки от датасета(студенты ): 45.64
Процент ошибки от датасета(учителя ): 45.02

```sql
select
    -- 1. всего студентов в таблице (и мальчики, и девочки)
    count(*) as total_students,

    -- 2. сколько девочек с ошибкой в фамилии
    count(case when 
        gender = 'F' 
        and split_part(full_name, ' ', 1) not in ('Ким', 'Ли') 
        and split_part(full_name, ' ', 1) not like '%а'
    then 1 end) as invalid_female_lastnames,

    -- 3. процент ошибок от всех студентов 
    round(
        count(case when 
            gender = 'F' 
            and split_part(full_name, ' ', 1) not in ('Ким', 'Ли') 
            and split_part(full_name, ' ', 1) not like '%а'
        then 1 end) * 100.0 / count(*), 
    2) as error_percentage

from students;



select
    -- 1. сколько всего учителей в таблице (и мужчины, и женщины)
    count(*) as total_teachers,

    -- 2. сколько учителей-женщин имеют ошибку в фамилии (не на "а", и это не Ким/Ли)
    count(case when
        (split_part(full_name, ' ', 3) like '%овна' or split_part(full_name, ' ', 3) like '%евна')
        and split_part(full_name, ' ', 1) not in ('Ким', 'Ли')
        and split_part(full_name, ' ', 1) not like '%а'
    then 1 end) as invalid_female_lastnames,

    -- 3. процент ошибок от всего датасета
    round(
        count(case when
            (split_part(full_name, ' ', 3) like '%овна' or split_part(full_name, ' ', 3) like '%евна')
            and split_part(full_name, ' ', 1) not in ('Ким', 'Ли')
            and split_part(full_name, ' ', 1) not like '%а'
        then 1 end) * 100.0 / count(*),
    2) as error_percentage

from raw.teachers;

```