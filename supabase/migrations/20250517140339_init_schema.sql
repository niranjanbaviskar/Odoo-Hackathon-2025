


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."session_status" AS ENUM (
    'pending',
    'active',
    'closed'
);


ALTER TYPE "public"."session_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_user_progress"("user_uuid" "uuid") RETURNS TABLE("total_quizzes" bigint, "average_score" numeric, "topic_strengths" "jsonb", "topic_weaknesses" "jsonb", "improvement_areas" "text"[], "achievement_level" integer, "next_milestone" integer)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  WITH quiz_stats AS (
    SELECT
      COUNT(*) as quiz_count,
      AVG(CAST(score AS numeric) / CAST(total_questions AS numeric) * 100) as avg_score,
      jsonb_object_agg(
        topic,
        AVG(CAST(score AS numeric) / CAST(total_questions AS numeric) * 100)
      ) as topic_scores
    FROM quiz_history
    WHERE user_id = user_uuid
    GROUP BY user_id
  )
  SELECT
    quiz_count,
    ROUND(avg_score, 2),
    (SELECT jsonb_object_agg(key, value)
     FROM jsonb_each(topic_scores)
     WHERE CAST(value AS numeric) >= 70),
    (SELECT jsonb_object_agg(key, value)
     FROM jsonb_each(topic_scores)
     WHERE CAST(value AS numeric) < 70),
    ARRAY(
      SELECT key
      FROM jsonb_each(topic_scores)
      WHERE CAST(value AS numeric) < 70
      ORDER BY value ASC
      LIMIT 3
    ),
    CASE
      WHEN quiz_count < 10 THEN 1
      WHEN quiz_count < 25 THEN 2
      WHEN quiz_count < 50 THEN 3
      ELSE 4
    END,
    CASE
      WHEN quiz_count < 10 THEN 10
      WHEN quiz_count < 25 THEN 25
      WHEN quiz_count < 50 THEN 50
      ELSE quiz_count + 10
    END
  FROM quiz_stats;
END;
$$;


ALTER FUNCTION "public"."calculate_user_progress"("user_uuid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_course_rating"("course_uuid" "uuid") RETURNS TABLE("average_rating" numeric, "total_ratings" bigint)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    ROUND(AVG(rating)::numeric, 1) as average_rating,
    COUNT(*) as total_ratings
  FROM course_ratings
  WHERE course_id = course_uuid;
END;
$$;


ALTER FUNCTION "public"."get_course_rating"("course_uuid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_thread_views"("thread_uuid" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE threads
  SET views = views + 1
  WHERE id = thread_uuid;
END;
$$;


ALTER FUNCTION "public"."increment_thread_views"("thread_uuid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_user_coins"("user_id" "uuid", "coins_to_add" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE profiles
  SET coins = coins + coins_to_add
  WHERE id = user_id;
END;
$$;


ALTER FUNCTION "public"."increment_user_coins"("user_id" "uuid", "coins_to_add" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_expert"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM experts 
    WHERE email = auth.jwt()->>'email'
  );
END;
$$;


ALTER FUNCTION "public"."is_expert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_api_key_last_used"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE api_keys
  SET last_used = now()
  WHERE key = current_setting('request.header.x-api-key', true);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_api_key_last_used"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_vote_counts"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.vote_type = 'upvote' THEN
      UPDATE community_messages
      SET upvotes = upvotes + 1
      WHERE id = NEW.message_id;
    ELSE
      UPDATE community_messages
      SET downvotes = downvotes + 1
      WHERE id = NEW.message_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.vote_type = 'upvote' THEN
      UPDATE community_messages
      SET upvotes = upvotes - 1
      WHERE id = OLD.message_id;
    ELSE
      UPDATE community_messages
      SET downvotes = downvotes - 1
      WHERE id = OLD.message_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."update_vote_counts"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."ai_responses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "whiteboard_id" "uuid" NOT NULL,
    "response_text" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "drawing_data" "jsonb"
);


ALTER TABLE "public"."ai_responses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."api_keys" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "key" "text" NOT NULL,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_used" timestamp with time zone,
    CONSTRAINT "api_keys_key_length" CHECK (("length"("key") >= 32))
);


ALTER TABLE "public"."api_keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bookmarks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "resource_id" "uuid",
    "course_id" "uuid",
    "quiz_id" "uuid",
    "type" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "bookmarks_type_check" CHECK (("type" = ANY (ARRAY['resource'::"text", 'course'::"text", 'quiz'::"text"]))),
    CONSTRAINT "one_reference_only" CHECK ((((
CASE
    WHEN ("resource_id" IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN ("course_id" IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN ("quiz_id" IS NOT NULL) THEN 1
    ELSE 0
END) = 1))
);


ALTER TABLE "public"."bookmarks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chapters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "content" "text" NOT NULL,
    "order_index" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "speech_url" "text",
    "speech_status" "text" DEFAULT 'pending'::"text",
    "speech_error" "text",
    CONSTRAINT "chapters_speech_status_check" CHECK (("speech_status" = ANY (ARRAY['pending'::"text", 'generating'::"text", 'completed'::"text", 'error'::"text"])))
);


ALTER TABLE "public"."chapters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "uuid",
    "role" "text" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    CONSTRAINT "chat_messages_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'assistant'::"text"])))
);


ALTER TABLE "public"."chat_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "title" "text" DEFAULT 'Chat Session'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."chat_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."codebooks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "language" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."codebooks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."communities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "tags" "text"[] DEFAULT '{}'::"text"[],
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."communities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "coins" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."communities_with_users" AS
 SELECT "c"."id",
    "c"."title",
    "c"."description",
    "c"."tags",
    "c"."user_id",
    "c"."created_at",
    "c"."updated_at",
    "p"."name" AS "user_name"
   FROM ("public"."communities" "c"
     JOIN "public"."profiles" "p" ON (("p"."id" = "c"."user_id")));


ALTER TABLE "public"."communities_with_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."community_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "community_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "upvotes" integer DEFAULT 0,
    "downvotes" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."community_messages" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."community_messages_with_users" AS
 SELECT "cm"."id",
    "cm"."community_id",
    "cm"."user_id",
    "cm"."content",
    "cm"."upvotes",
    "cm"."downvotes",
    "cm"."created_at",
    "cm"."updated_at",
    "p"."name" AS "user_name"
   FROM ("public"."community_messages" "cm"
     JOIN "public"."profiles" "p" ON (("p"."id" = "cm"."user_id")));


ALTER TABLE "public"."community_messages_with_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."course_ratings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "course_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "rating" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "valid_rating" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."course_ratings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."courses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "is_public" boolean DEFAULT false
);


ALTER TABLE "public"."courses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."experts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."experts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."message_votes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "vote_type" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "message_votes_vote_type_check" CHECK (("vote_type" = ANY (ARRAY['upvote'::"text", 'downvote'::"text"])))
);


ALTER TABLE "public"."message_votes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notebooks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."notebooks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."playgrounds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "code" "text" DEFAULT ''::"text",
    "language" "text" NOT NULL,
    "codebook_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "order_index" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."playgrounds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."practice_results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "exercise_type" "text" NOT NULL,
    "question" "text" NOT NULL,
    "user_answer" "text" NOT NULL,
    "correct_answer" "text" NOT NULL,
    "is_correct" boolean NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."practice_results" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."profiles_count_view" AS
 SELECT "count"(*) AS "profiles_count"
   FROM "public"."profiles";


ALTER TABLE "public"."profiles_count_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quiz_analytics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "quiz_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "analysis" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."quiz_analytics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quiz_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "topic" "text" NOT NULL,
    "score" integer NOT NULL,
    "total_questions" integer NOT NULL,
    "questions" "jsonb" NOT NULL,
    "answers" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "coins_earned" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."quiz_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."resources" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "file_url" "text" NOT NULL,
    "thumbnail_url" "text",
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."resources" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roadmap_courses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "roadmap_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "order_index" integer NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."roadmap_courses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."roadmaps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "content" "jsonb" NOT NULL,
    "user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."roadmaps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."saved_exercises" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "type" "text" NOT NULL,
    "question" "text" NOT NULL,
    "options" "text"[],
    "correct_answer" "text" NOT NULL,
    "explanation" "text" NOT NULL,
    "passage" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."saved_exercises" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."saved_vocabulary" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "word" "text" NOT NULL,
    "definition" "text" NOT NULL,
    "examples" "text"[] NOT NULL,
    "synonyms" "text"[] NOT NULL,
    "level" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."saved_vocabulary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_achievements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "total_quizzes" integer DEFAULT 0,
    "total_correct_answers" integer DEFAULT 0,
    "average_accuracy" numeric(5,2) DEFAULT 0,
    "streak_count" integer DEFAULT 0,
    "last_quiz_date" timestamp with time zone,
    "badges" "jsonb" DEFAULT '[]'::"jsonb",
    "level" integer DEFAULT 1,
    "xp_points" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."user_achievements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."whiteboards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "notebook_id" "uuid",
    "order_index" integer DEFAULT 0,
    "drawing_data" "jsonb" DEFAULT '[]'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."whiteboards" OWNER TO "postgres";


ALTER TABLE ONLY "public"."ai_responses"
    ADD CONSTRAINT "ai_responses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bookmarks"
    ADD CONSTRAINT "bookmarks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chapters"
    ADD CONSTRAINT "chapters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_sessions"
    ADD CONSTRAINT "chat_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."codebooks"
    ADD CONSTRAINT "codebooks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."communities"
    ADD CONSTRAINT "communities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."community_messages"
    ADD CONSTRAINT "community_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_ratings"
    ADD CONSTRAINT "course_ratings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."experts"
    ADD CONSTRAINT "experts_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."experts"
    ADD CONSTRAINT "experts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."message_votes"
    ADD CONSTRAINT "message_votes_message_id_user_id_key" UNIQUE ("message_id", "user_id");



ALTER TABLE ONLY "public"."message_votes"
    ADD CONSTRAINT "message_votes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notebooks"
    ADD CONSTRAINT "notebooks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."playgrounds"
    ADD CONSTRAINT "playgrounds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."practice_results"
    ADD CONSTRAINT "practice_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quiz_analytics"
    ADD CONSTRAINT "quiz_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quiz_analytics"
    ADD CONSTRAINT "quiz_analytics_quiz_id_key" UNIQUE ("quiz_id");



ALTER TABLE ONLY "public"."quiz_history"
    ADD CONSTRAINT "quiz_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."resources"
    ADD CONSTRAINT "resources_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roadmap_courses"
    ADD CONSTRAINT "roadmap_courses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roadmaps"
    ADD CONSTRAINT "roadmaps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."saved_exercises"
    ADD CONSTRAINT "saved_exercises_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."saved_vocabulary"
    ADD CONSTRAINT "saved_vocabulary_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."course_ratings"
    ADD CONSTRAINT "unique_user_course_rating" UNIQUE ("course_id", "user_id");



ALTER TABLE ONLY "public"."user_achievements"
    ADD CONSTRAINT "user_achievements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."whiteboards"
    ADD CONSTRAINT "whiteboards_pkey" PRIMARY KEY ("id");



CREATE INDEX "bookmarks_course_id_idx" ON "public"."bookmarks" USING "btree" ("course_id");



CREATE INDEX "bookmarks_quiz_id_idx" ON "public"."bookmarks" USING "btree" ("quiz_id");



CREATE INDEX "bookmarks_resource_id_idx" ON "public"."bookmarks" USING "btree" ("resource_id");



CREATE INDEX "bookmarks_user_id_idx" ON "public"."bookmarks" USING "btree" ("user_id");



CREATE INDEX "chat_messages_content_idx" ON "public"."chat_messages" USING "gin" ("to_tsvector"('"english"'::"regconfig", "content"));



CREATE INDEX "chat_messages_session_id_idx" ON "public"."chat_messages" USING "btree" ("session_id");



CREATE INDEX "chat_messages_user_id_idx" ON "public"."chat_messages" USING "btree" ("user_id");



CREATE INDEX "chat_sessions_user_id_idx" ON "public"."chat_sessions" USING "btree" ("user_id");



CREATE INDEX "codebooks_user_id_idx" ON "public"."codebooks" USING "btree" ("user_id");



CREATE INDEX "idx_chapters_speech_status" ON "public"."chapters" USING "btree" ("speech_status");



CREATE INDEX "idx_roadmap_courses_order_index" ON "public"."roadmap_courses" USING "btree" ("order_index");



CREATE INDEX "idx_roadmap_courses_roadmap_id" ON "public"."roadmap_courses" USING "btree" ("roadmap_id");



CREATE INDEX "idx_roadmap_courses_user_id" ON "public"."roadmap_courses" USING "btree" ("user_id");



CREATE INDEX "playgrounds_codebook_id_idx" ON "public"."playgrounds" USING "btree" ("codebook_id");



CREATE INDEX "playgrounds_user_id_idx" ON "public"."playgrounds" USING "btree" ("user_id");



CREATE INDEX "practice_results_user_id_idx" ON "public"."practice_results" USING "btree" ("user_id");



CREATE INDEX "saved_exercises_user_id_idx" ON "public"."saved_exercises" USING "btree" ("user_id");



CREATE INDEX "saved_vocabulary_user_id_idx" ON "public"."saved_vocabulary" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "update_chapters_updated_at" BEFORE UPDATE ON "public"."chapters" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_communities_updated_at" BEFORE UPDATE ON "public"."communities" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_community_messages_updated_at" BEFORE UPDATE ON "public"."community_messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_course_ratings_updated_at" BEFORE UPDATE ON "public"."course_ratings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_courses_updated_at" BEFORE UPDATE ON "public"."courses" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_notebooks_updated_at" BEFORE UPDATE ON "public"."notebooks" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_roadmap_courses_updated_at" BEFORE UPDATE ON "public"."roadmap_courses" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_roadmaps_updated_at" BEFORE UPDATE ON "public"."roadmaps" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_vote_counts_trigger" AFTER INSERT OR DELETE ON "public"."message_votes" FOR EACH ROW EXECUTE FUNCTION "public"."update_vote_counts"();



CREATE OR REPLACE TRIGGER "update_whiteboards_updated_at" BEFORE UPDATE ON "public"."whiteboards" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."ai_responses"
    ADD CONSTRAINT "ai_responses_whiteboard_id_fkey" FOREIGN KEY ("whiteboard_id") REFERENCES "public"."whiteboards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookmarks"
    ADD CONSTRAINT "bookmarks_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookmarks"
    ADD CONSTRAINT "bookmarks_quiz_id_fkey" FOREIGN KEY ("quiz_id") REFERENCES "public"."quiz_history"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookmarks"
    ADD CONSTRAINT "bookmarks_resource_id_fkey" FOREIGN KEY ("resource_id") REFERENCES "public"."resources"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookmarks"
    ADD CONSTRAINT "bookmarks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chapters"
    ADD CONSTRAINT "chapters_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."chat_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_sessions"
    ADD CONSTRAINT "chat_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."codebooks"
    ADD CONSTRAINT "codebooks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."communities"
    ADD CONSTRAINT "communities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_messages"
    ADD CONSTRAINT "community_messages_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "public"."communities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_messages"
    ADD CONSTRAINT "community_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."course_ratings"
    ADD CONSTRAINT "course_ratings_course_id_fkey" FOREIGN KEY ("course_id") REFERENCES "public"."courses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."course_ratings"
    ADD CONSTRAINT "course_ratings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."courses"
    ADD CONSTRAINT "courses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_votes"
    ADD CONSTRAINT "message_votes_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."community_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_votes"
    ADD CONSTRAINT "message_votes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notebooks"
    ADD CONSTRAINT "notebooks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."playgrounds"
    ADD CONSTRAINT "playgrounds_codebook_id_fkey" FOREIGN KEY ("codebook_id") REFERENCES "public"."codebooks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."playgrounds"
    ADD CONSTRAINT "playgrounds_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."practice_results"
    ADD CONSTRAINT "practice_results_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quiz_analytics"
    ADD CONSTRAINT "quiz_analytics_quiz_id_fkey" FOREIGN KEY ("quiz_id") REFERENCES "public"."quiz_history"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quiz_analytics"
    ADD CONSTRAINT "quiz_analytics_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quiz_history"
    ADD CONSTRAINT "quiz_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."resources"
    ADD CONSTRAINT "resources_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."roadmap_courses"
    ADD CONSTRAINT "roadmap_courses_roadmap_id_fkey" FOREIGN KEY ("roadmap_id") REFERENCES "public"."roadmaps"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."roadmap_courses"
    ADD CONSTRAINT "roadmap_courses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."roadmaps"
    ADD CONSTRAINT "roadmaps_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saved_exercises"
    ADD CONSTRAINT "saved_exercises_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saved_vocabulary"
    ADD CONSTRAINT "saved_vocabulary_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_achievements"
    ADD CONSTRAINT "user_achievements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."whiteboards"
    ADD CONSTRAINT "whiteboards_notebook_id_fkey" FOREIGN KEY ("notebook_id") REFERENCES "public"."notebooks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."whiteboards"
    ADD CONSTRAINT "whiteboards_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Allow bot to create chapters" ON "public"."chapters" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "auth"."users"
  WHERE (("auth"."uid"() = "users"."id") AND (("users"."email")::"text" = 'system@SkillSwap.bot'::"text")))));



CREATE POLICY "Allow bot to create courses" ON "public"."courses" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "auth"."users"
  WHERE (("auth"."uid"() = "users"."id") AND (("users"."email")::"text" = 'system@SkillSwap.bot'::"text")))));



CREATE POLICY "Allow users to create their own roadmaps" ON "public"."roadmaps" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Allow users to delete their own roadmaps" ON "public"."roadmaps" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Allow users to read any roadmap" ON "public"."roadmaps" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow users to update their own roadmaps" ON "public"."roadmaps" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Anyone can read chapters" ON "public"."chapters" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Anyone can read course ratings" ON "public"."course_ratings" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Anyone can read courses" ON "public"."courses" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Anyone can read resources" ON "public"."resources" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Anyone can view communities" ON "public"."communities" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Anyone can view messages" ON "public"."community_messages" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Experts can update their own profile" ON "public"."experts" FOR UPDATE TO "authenticated" USING (("auth"."email"() = "email")) WITH CHECK (("auth"."email"() = "email"));



CREATE POLICY "Experts can view their own profile" ON "public"."experts" FOR SELECT TO "authenticated" USING (("auth"."email"() = "email"));



CREATE POLICY "Users can create analytics for their quizzes" ON "public"."quiz_analytics" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create chapters for own courses" ON "public"."chapters" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."courses"
  WHERE (("courses"."id" = "chapters"."course_id") AND ("courses"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can create communities" ON "public"."communities" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create messages" ON "public"."community_messages" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create own chat sessions" ON "public"."chat_sessions" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create own courses" ON "public"."courses" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create own messages" ON "public"."chat_messages" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create own practice results" ON "public"."practice_results" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create own resources" ON "public"."resources" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create responses for their whiteboards" ON "public"."ai_responses" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."whiteboards"
  WHERE (("whiteboards"."id" = "ai_responses"."whiteboard_id") AND ("whiteboards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can create roadmap courses" ON "public"."roadmap_courses" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create saved exercises" ON "public"."saved_exercises" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create saved vocabulary" ON "public"."saved_vocabulary" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own bookmarks" ON "public"."bookmarks" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own chat sessions" ON "public"."chat_sessions" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own codebooks" ON "public"."codebooks" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own notebooks" ON "public"."notebooks" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own playgrounds" ON "public"."playgrounds" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own ratings" ON "public"."course_ratings" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own whiteboards" ON "public"."whiteboards" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create votes" ON "public"."message_votes" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own API keys" ON "public"."api_keys" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own saved exercises" ON "public"."saved_exercises" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own saved vocabulary" ON "public"."saved_vocabulary" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own bookmarks" ON "public"."bookmarks" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own chat sessions" ON "public"."chat_sessions" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own codebooks" ON "public"."codebooks" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own communities" ON "public"."communities" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own messages" ON "public"."community_messages" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own notebooks" ON "public"."notebooks" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own playgrounds" ON "public"."playgrounds" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own ratings" ON "public"."course_ratings" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own roadmap courses" ON "public"."roadmap_courses" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own votes" ON "public"."message_votes" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own whiteboards" ON "public"."whiteboards" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert own API keys" ON "public"."api_keys" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert own profile" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can insert own quiz history" ON "public"."quiz_history" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read any roadmap course" ON "public"."roadmap_courses" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Users can read own API keys" ON "public"."api_keys" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read own achievements" ON "public"."user_achievements" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can read own quiz history" ON "public"."quiz_history" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read their own analytics" ON "public"."quiz_analytics" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update chapters for own courses" ON "public"."chapters" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."courses"
  WHERE (("courses"."id" = "chapters"."course_id") AND ("courses"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can update own API keys" ON "public"."api_keys" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own courses" ON "public"."courses" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own chat sessions" ON "public"."chat_sessions" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own codebooks" ON "public"."codebooks" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own communities" ON "public"."communities" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own messages" ON "public"."community_messages" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own notebooks" ON "public"."notebooks" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own playgrounds" ON "public"."playgrounds" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own ratings" ON "public"."course_ratings" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own roadmap courses" ON "public"."roadmap_courses" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own votes" ON "public"."message_votes" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own whiteboards" ON "public"."whiteboards" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own chat sessions" ON "public"."chat_sessions" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own messages" ON "public"."chat_messages" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own practice results" ON "public"."practice_results" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own saved exercises" ON "public"."saved_exercises" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own saved vocabulary" ON "public"."saved_vocabulary" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view responses for their whiteboards" ON "public"."ai_responses" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."whiteboards"
  WHERE (("whiteboards"."id" = "ai_responses"."whiteboard_id") AND ("whiteboards"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view their own bookmarks" ON "public"."bookmarks" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own chat sessions" ON "public"."chat_sessions" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own codebooks" ON "public"."codebooks" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own notebooks" ON "public"."notebooks" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own playgrounds" ON "public"."playgrounds" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view their own whiteboards" ON "public"."whiteboards" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view votes" ON "public"."message_votes" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."ai_responses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."api_keys" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."codebooks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."communities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."community_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."experts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "global_select_profiles_for_count" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() IS NOT NULL));



ALTER TABLE "public"."message_votes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notebooks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."playgrounds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."practice_results" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."resources" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."roadmap_courses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_achievements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."whiteboards" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_user_progress"("user_uuid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_user_progress"("user_uuid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_user_progress"("user_uuid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_course_rating"("course_uuid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_course_rating"("course_uuid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_course_rating"("course_uuid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_thread_views"("thread_uuid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_thread_views"("thread_uuid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_thread_views"("thread_uuid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_user_coins"("user_id" "uuid", "coins_to_add" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_user_coins"("user_id" "uuid", "coins_to_add" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_user_coins"("user_id" "uuid", "coins_to_add" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_expert"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_expert"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_expert"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_api_key_last_used"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_api_key_last_used"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_api_key_last_used"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_vote_counts"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_vote_counts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_vote_counts"() TO "service_role";



GRANT ALL ON TABLE "public"."ai_responses" TO "anon";
GRANT ALL ON TABLE "public"."ai_responses" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_responses" TO "service_role";



GRANT ALL ON TABLE "public"."api_keys" TO "anon";
GRANT ALL ON TABLE "public"."api_keys" TO "authenticated";
GRANT ALL ON TABLE "public"."api_keys" TO "service_role";



GRANT ALL ON TABLE "public"."bookmarks" TO "anon";
GRANT ALL ON TABLE "public"."bookmarks" TO "authenticated";
GRANT ALL ON TABLE "public"."bookmarks" TO "service_role";



GRANT ALL ON TABLE "public"."chapters" TO "anon";
GRANT ALL ON TABLE "public"."chapters" TO "authenticated";
GRANT ALL ON TABLE "public"."chapters" TO "service_role";



GRANT ALL ON TABLE "public"."chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_messages" TO "service_role";



GRANT ALL ON TABLE "public"."chat_sessions" TO "anon";
GRANT ALL ON TABLE "public"."chat_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."codebooks" TO "anon";
GRANT ALL ON TABLE "public"."codebooks" TO "authenticated";
GRANT ALL ON TABLE "public"."codebooks" TO "service_role";



GRANT ALL ON TABLE "public"."communities" TO "anon";
GRANT ALL ON TABLE "public"."communities" TO "authenticated";
GRANT ALL ON TABLE "public"."communities" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."communities_with_users" TO "anon";
GRANT ALL ON TABLE "public"."communities_with_users" TO "authenticated";
GRANT ALL ON TABLE "public"."communities_with_users" TO "service_role";



GRANT ALL ON TABLE "public"."community_messages" TO "anon";
GRANT ALL ON TABLE "public"."community_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."community_messages" TO "service_role";



GRANT ALL ON TABLE "public"."community_messages_with_users" TO "anon";
GRANT ALL ON TABLE "public"."community_messages_with_users" TO "authenticated";
GRANT ALL ON TABLE "public"."community_messages_with_users" TO "service_role";



GRANT ALL ON TABLE "public"."course_ratings" TO "anon";
GRANT ALL ON TABLE "public"."course_ratings" TO "authenticated";
GRANT ALL ON TABLE "public"."course_ratings" TO "service_role";



GRANT ALL ON TABLE "public"."courses" TO "anon";
GRANT ALL ON TABLE "public"."courses" TO "authenticated";
GRANT ALL ON TABLE "public"."courses" TO "service_role";



GRANT ALL ON TABLE "public"."experts" TO "anon";
GRANT ALL ON TABLE "public"."experts" TO "authenticated";
GRANT ALL ON TABLE "public"."experts" TO "service_role";



GRANT ALL ON TABLE "public"."message_votes" TO "anon";
GRANT ALL ON TABLE "public"."message_votes" TO "authenticated";
GRANT ALL ON TABLE "public"."message_votes" TO "service_role";



GRANT ALL ON TABLE "public"."notebooks" TO "anon";
GRANT ALL ON TABLE "public"."notebooks" TO "authenticated";
GRANT ALL ON TABLE "public"."notebooks" TO "service_role";



GRANT ALL ON TABLE "public"."playgrounds" TO "anon";
GRANT ALL ON TABLE "public"."playgrounds" TO "authenticated";
GRANT ALL ON TABLE "public"."playgrounds" TO "service_role";



GRANT ALL ON TABLE "public"."practice_results" TO "anon";
GRANT ALL ON TABLE "public"."practice_results" TO "authenticated";
GRANT ALL ON TABLE "public"."practice_results" TO "service_role";



GRANT ALL ON TABLE "public"."profiles_count_view" TO "anon";
GRANT ALL ON TABLE "public"."profiles_count_view" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles_count_view" TO "service_role";



GRANT ALL ON TABLE "public"."quiz_analytics" TO "anon";
GRANT ALL ON TABLE "public"."quiz_analytics" TO "authenticated";
GRANT ALL ON TABLE "public"."quiz_analytics" TO "service_role";



GRANT ALL ON TABLE "public"."quiz_history" TO "anon";
GRANT ALL ON TABLE "public"."quiz_history" TO "authenticated";
GRANT ALL ON TABLE "public"."quiz_history" TO "service_role";



GRANT ALL ON TABLE "public"."resources" TO "anon";
GRANT ALL ON TABLE "public"."resources" TO "authenticated";
GRANT ALL ON TABLE "public"."resources" TO "service_role";



GRANT ALL ON TABLE "public"."roadmap_courses" TO "anon";
GRANT ALL ON TABLE "public"."roadmap_courses" TO "authenticated";
GRANT ALL ON TABLE "public"."roadmap_courses" TO "service_role";



GRANT ALL ON TABLE "public"."roadmaps" TO "anon";
GRANT ALL ON TABLE "public"."roadmaps" TO "authenticated";
GRANT ALL ON TABLE "public"."roadmaps" TO "service_role";



GRANT ALL ON TABLE "public"."saved_exercises" TO "anon";
GRANT ALL ON TABLE "public"."saved_exercises" TO "authenticated";
GRANT ALL ON TABLE "public"."saved_exercises" TO "service_role";



GRANT ALL ON TABLE "public"."saved_vocabulary" TO "anon";
GRANT ALL ON TABLE "public"."saved_vocabulary" TO "authenticated";
GRANT ALL ON TABLE "public"."saved_vocabulary" TO "service_role";



GRANT ALL ON TABLE "public"."user_achievements" TO "anon";
GRANT ALL ON TABLE "public"."user_achievements" TO "authenticated";
GRANT ALL ON TABLE "public"."user_achievements" TO "service_role";



GRANT ALL ON TABLE "public"."whiteboards" TO "anon";
GRANT ALL ON TABLE "public"."whiteboards" TO "authenticated";
GRANT ALL ON TABLE "public"."whiteboards" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






RESET ALL;
