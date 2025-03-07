-- ### Configure partitions as needed
CREATE TABLE commands_default PARTITION OF commands DEFAULT;
-- CREATE TABLE commands_0 PARTITION OF commands FOR VALUES FROM (1) TO (100e6);
-- CREATE TABLE commands_1 PARTITION OF commands FOR VALUES FROM (100e6) TO (200e6);
-- CREATE TABLE commands_2 PARTITION OF commands FOR VALUES FROM (200e6) TO (300e6);
-- CREATE TABLE commands_3 PARTITION OF commands FOR VALUES FROM (300e6) TO (400e6);

-- ### Configure partitions as needed
CREATE TABLE aggregates_default PARTITION OF aggregates DEFAULT;
-- CREATE TABLE aggregates_0 PARTITION OF aggregates FOR VALUES FROM (MINVALUE) TO ('10000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_1 PARTITION OF aggregates FOR VALUES FROM ('10000000-0000-0000-0000-000000000000') TO ('20000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_2 PARTITION OF aggregates FOR VALUES FROM ('20000000-0000-0000-0000-000000000000') TO ('30000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_3 PARTITION OF aggregates FOR VALUES FROM ('30000000-0000-0000-0000-000000000000') TO ('40000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_4 PARTITION OF aggregates FOR VALUES FROM ('40000000-0000-0000-0000-000000000000') TO ('50000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_5 PARTITION OF aggregates FOR VALUES FROM ('50000000-0000-0000-0000-000000000000') TO ('60000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_6 PARTITION OF aggregates FOR VALUES FROM ('60000000-0000-0000-0000-000000000000') TO ('70000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_7 PARTITION OF aggregates FOR VALUES FROM ('70000000-0000-0000-0000-000000000000') TO ('80000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_8 PARTITION OF aggregates FOR VALUES FROM ('80000000-0000-0000-0000-000000000000') TO ('90000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_9 PARTITION OF aggregates FOR VALUES FROM ('90000000-0000-0000-0000-000000000000') TO ('a0000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_a PARTITION OF aggregates FOR VALUES FROM ('a0000000-0000-0000-0000-000000000000') TO ('b0000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_b PARTITION OF aggregates FOR VALUES FROM ('b0000000-0000-0000-0000-000000000000') TO ('c0000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_c PARTITION OF aggregates FOR VALUES FROM ('c0000000-0000-0000-0000-000000000000') TO ('d0000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_d PARTITION OF aggregates FOR VALUES FROM ('d0000000-0000-0000-0000-000000000000') TO ('e0000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_e PARTITION OF aggregates FOR VALUES FROM ('e0000000-0000-0000-0000-000000000000') TO ('f0000000-0000-0000-0000-000000000000');
-- CREATE TABLE aggregates_f PARTITION OF aggregates FOR VALUES FROM ('f0000000-0000-0000-0000-000000000000') TO (MAXVALUE);

-- ### Configure partitions as needed
CREATE TABLE events_default PARTITION OF events DEFAULT;
-- CREATE TABLE events_2023_and_earlier PARTITION OF events FOR VALUES FROM ('Y00') TO ('Y24');
-- CREATE TABLE events_2024 PARTITION OF events FOR VALUES FROM ('Y24') TO ('Y25');
-- CREATE TABLE events_2025 PARTITION OF events FOR VALUES FROM ('Y25') TO ('Y26');
-- CREATE TABLE events_2026 PARTITION OF events FOR VALUES FROM ('Y26') TO ('Y27');
-- CREATE TABLE events_2027_and_later PARTITION OF events FOR VALUES FROM ('Y27') TO ('Y99');
-- CREATE TABLE events_aggregate PARTITION OF events FOR VALUES FROM ('A') TO ('Ag');
