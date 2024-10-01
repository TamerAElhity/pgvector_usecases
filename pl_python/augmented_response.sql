-- FUNCTION: public.augmented_response(character varying, character varying)

-- DROP FUNCTION IF EXISTS public.augmented_response(character varying, character varying);

CREATE OR REPLACE FUNCTION public.augmented_response(
	dataset_name character varying,
	question character varying,
	llm_model character varying,
	question_to_model BOOL)
    RETURNS text AS $$

import os
import time
import json

last_checkpoint_time = time.time()

#***********************************************************
#***********************************************************
#*************Caching Python Libraries**********************
#****************Ollama*************************************
#***********************************************************

# Load the model with caching using the SD dictionary
if 'cached_ollama' not in SD:
    try:
        import ollama
        # Assuming ollama.embeddings directly initializes or needs a model loading function
        SD['cached_ollama'] = ollama # ollama.embeddings(model="mxbai-embed-large", prompt="") #zephyr:7b
        plpy.notice("Model 'mxbai-embed-large' loaded and cached successfully.")
    except Exception as e:
        plpy.error(f"Failed to load model: {str(e)}")

plpy.notice(f"Model loading time: {time.time() - last_checkpoint_time:.2f} seconds.")
last_checkpoint_time = time.time()
model = SD['cached_ollama']

#***********************************************************
#***********************************************************
#*******PGVector SQL statement to find similarities*********
#***********************************************************
#***********************************************************

plan = plpy.prepare(f"""
		SELECT id, content, 1-(embedding <=> $1) AS DIST
			FROM {dataset_name}
			WHERE (1-(embedding <=> $1)) > 0.5
			ORDER BY DIST DESC;
			""", ["vector"])

#***********************************************************
#***********************************************************
#*******Generate embedding for the provided question********
#***********and search for similar chunks in PGVector*******
#***********************************************************
if question_to_model == False:
	question_embedding = model.embeddings(model="mxbai-embed-large", prompt=question)

	plpy.notice(f"Generate question embedding time: {time.time() - last_checkpoint_time:.2f} seconds.")
	last_checkpoint_time = time.time()

	rv = plpy.execute(plan,[question_embedding['embedding']],100)

#plpy.notice(f"similarties query execution time: {time.time() - last_checkpoint_time:.2f} seconds.")
#last_checkpoint_time = time.time()

#***********************************************************
#***********************************************************
#*******Concatenate similar chunks as an input to **********
#***********llm model to generate augemented resposne*******
#***********************************************************
chunk_count=0
pg_time=0
if question_to_model == False:
	query_result=''
	generated_result=''
	#concatenate the similar chunks
	
	for row in rv:
	    query_result = query_result + " | " + row['content']
	    chunk_count = chunk_count + 1
	plpy.notice(f"similarities query and row fetching prcocessing time: {time.time() - last_checkpoint_time:.2f} seconds.")
		
	pg_time = f"{time.time() - last_checkpoint_time:.2f}"
	last_checkpoint_time = time.time()

#***********************************************************
#***********************************************************
#*******Generate augemented response using LLM for the *****
#***************similar chuncks*****************************
#***********************************************************

if question_to_model == False:
	if len(rv)>0 :
		#generate content for the found similar chunks
	    tmp = "Use this retrieved data:" + query_result + ". to answer this question: " + question
	    generated_result = model.generate(model=llm_model,prompt=tmp)['response']
	else:
	    generated_result = "No data found to answer the question: "
	
else:
	generated_result = model.generate(model=llm_model,prompt=question)['response']
plpy.notice(f"model generate time: {time.time() - last_checkpoint_time:.2f} seconds.")
llm_time = f"{time.time() - last_checkpoint_time:.2f}"
last_checkpoint_time = time.time()

resp = {}
resp['llm_response'] = generated_result
resp['pg_time'] = pg_time
resp['llm_time'] = llm_time
resp['chunk_count']=chunk_count

return json.dumps(resp)
$$ LANGUAGE plpython3u;
