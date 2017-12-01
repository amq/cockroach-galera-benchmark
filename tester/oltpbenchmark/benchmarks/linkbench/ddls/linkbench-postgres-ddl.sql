DROP TABLE IF EXISTS linktable;
DROP TABLE IF EXISTS counttable;
DROP TABLE IF EXISTS nodetable;

CREATE TABLE linktable (
  id1 numeric(20) NOT NULL DEFAULT '0',
  id2 numeric(20) NOT NULL DEFAULT '0',
  link_type numeric(20) NOT NULL DEFAULT '0',
  visibility smallint NOT NULL DEFAULT '0',
  data bytes NOT NULL DEFAULT '',
  time numeric(20) NOT NULL DEFAULT '0',
  version bigint NOT NULL DEFAULT '0',
  PRIMARY KEY (id1, id2, link_type)
);

CREATE INDEX id1_type on linktable (
id1, link_type, visibility, time, id2, version, data);

CREATE TABLE counttable (
  id numeric(20) NOT NULL DEFAULT '0',
  link_type numeric(20) NOT NULL DEFAULT '0',
  count int NOT NULL DEFAULT '0',
  time numeric(20) NOT NULL DEFAULT '0',
  version numeric(20) NOT NULL DEFAULT '0',
  PRIMARY KEY (id, link_type)
);

CREATE TABLE nodetable (
  id BIGSERIAL NOT NULL,
  type int NOT NULL,
  version numeric NOT NULL,
  time int NOT NULL,
  data bytes NOT NULL,
  PRIMARY KEY(id)
);

