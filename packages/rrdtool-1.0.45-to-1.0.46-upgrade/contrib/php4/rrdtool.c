/*
 *
 * php4_rrdtool.c
 *
 *	PHP interface to RRD Tool. (for php4/zend)
 *
 *
 *       Joe Miller, <joeym@ibizcorp.com>, <joeym@inficad.com> 
 *          iBIZ Technology Corp,  SkyLynx / Inficad Communications
 *          2/12/2000 & 7/18/2000
 *
 *       Jeffrey Wheat <jeff@cetlink.net> - 10/01/2002
 *       - Fixed to build with php-4.2.3
 *
 * See README, INSTALL, and USAGE files for more details.
 *
 * $Id: rrdtool.c,v 1.1.1.1 2002/02/26 10:21:20 oetiker Exp $
 *
 */

#include "php.h"
#include "rrd.h"
#include "php_config.h"
#include "php_rrdtool.h"

#if HAVE_RRDTOOL

function_entry rrdtool_functions[] = {
	PHP_FE(rrd_error, NULL)
	PHP_FE(rrd_clear_error, NULL)
	PHP_FE(rrd_graph, NULL)
	PHP_FE(rrd_last, NULL)
	PHP_FE(rrd_fetch, NULL)
	PHP_FE(rrd_update, NULL)
	PHP_FE(rrd_create, NULL)
	{NULL, NULL, NULL}
};

zend_module_entry rrdtool_module_entry = {
	STANDARD_MODULE_HEADER,
	"RRDTool",
	rrdtool_functions,
	NULL,
	NULL,
	NULL,
	NULL,
	PHP_MINFO(rrdtool),
	NO_VERSION_YET,
	STANDARD_MODULE_PROPERTIES,
};

#ifdef COMPILE_DL_RRDTOOL
ZEND_GET_MODULE(rrdtool)
#endif

PHP_MINFO_FUNCTION(rrdtool)
{
	php_info_print_table_start();
	php_info_print_table_header(2, "rrdtool support", "enabled");
	php_info_print_table_end();
}

//PHP_MINIT_FUNCTION(rrdtool)
//{
//	return SUCCESS;
//}


/* {{{ proto string rrd_error(void)
	Get the error message set by the last rrd tool function call */

PHP_FUNCTION(rrd_error)
{
	char *msg;

	if ( rrd_test_error() )
	{
		msg = rrd_get_error();        

		RETVAL_STRING(msg, 1);
		rrd_clear_error();
	}
	else
		return;
}
/* }}} */



/* {{{ proto void rrd_clear_error(void)
	Clear the error set by the last rrd tool function call */

PHP_FUNCTION(rrd_clear_error)
{
	if ( rrd_test_error() )
		rrd_clear_error();

	return;
}
/* }}} */



/* {{{ proto int rrd_update(string file, string opt) 
	Update an RRD file with values specified */

PHP_FUNCTION(rrd_update)
{
	pval *file, *opt;
	char **argv;

	if ( rrd_test_error() )
		rrd_clear_error();

	if ( ZEND_NUM_ARGS() == 2 && 
		 zend_get_parameters(ht, 2, &file, &opt) == SUCCESS )
	{
		convert_to_string(file);
		convert_to_string(opt);

		argv = (char **) emalloc(4 * sizeof(char *));

		argv[0] = "dummy";
		argv[1] = estrdup("update");
		argv[2] = estrdup(file->value.str.val);
		argv[3] = estrdup(opt->value.str.val);

		optind = 0; opterr = 0;
		if ( rrd_update(3, &argv[1]) != -1 )
		{
			RETVAL_TRUE;
		}
		else
		{
			RETVAL_FALSE;
		}
		efree(argv[1]); efree(argv[2]); efree(argv[3]);
		efree(argv);
	}
	else
	{
		WRONG_PARAM_COUNT;
	}
	return;
}
/* }}} */



/* {{{ proto int rrd_last(string file)
	Gets last update time of an RRD file */

PHP_FUNCTION(rrd_last)
{
	pval *file;
	unsigned long retval;

	char **argv = (char **) emalloc(3 * sizeof(char *));
    
	if ( rrd_test_error() )
		rrd_clear_error();
    
	if (zend_get_parameters(ht, 1, &file) == SUCCESS)
	{
		convert_to_string(file);

		argv[0] = "dummy";
		argv[1] = estrdup("last");
		argv[2] = estrdup(file->value.str.val);

		optind = 0; opterr = 0;
		retval = rrd_last(2, &argv[1]);

		efree(argv[1]);  efree(argv[2]);
		efree(argv);
		RETVAL_LONG(retval);
	}
	else
	{
		WRONG_PARAM_COUNT;
	}
	return;
}
/* }}} */


/* {{{ proto int rrd_create(string file, array args_arr, int argc)
	Create an RRD file with the options passed (passed via array) */ 

PHP_FUNCTION(rrd_create)
{
	pval *file, *args, *p_argc;
	pval *entry;
	char **argv;
	HashTable *args_arr;
	int argc, i;

	if ( rrd_test_error() )
		rrd_clear_error();

	if ( ZEND_NUM_ARGS() == 3 && 
		getParameters(ht, 3, &file, &args, &p_argc) == SUCCESS )
	{
		if ( args->type != IS_ARRAY )
		{ 
			php_error(E_WARNING, "2nd Variable passed to rrd_create is not an array!\n");
			RETURN_FALSE;
		}

		convert_to_long(p_argc);
		convert_to_string(file);
		
		convert_to_array(args);
		args_arr = args->value.ht;
		zend_hash_internal_pointer_reset(args_arr);

		argc = p_argc->value.lval + 3;
		argv = (char **) emalloc(argc * sizeof(char *));

		argv[0] = "dummy";
		argv[1] = estrdup("create");
		argv[2] = estrdup(file->value.str.val);

		for (i = 3; i < argc; i++) 
		{
			pval **dataptr;

			if ( zend_hash_get_current_data(args_arr, (void *) &dataptr) == FAILURE )
				continue;

			entry = *dataptr;

			if ( entry->type != IS_STRING )
				convert_to_string(entry);

			argv[i] = estrdup(entry->value.str.val);

			if ( i < argc )
				zend_hash_move_forward(args_arr);
		}
  
		optind = 0;  opterr = 0;

		if ( rrd_create(argc-1, &argv[1]) != -1 )
		{
			RETVAL_TRUE;
		}
		else
		{
			RETVAL_FALSE;
		}
		for (i = 1; i < argc; i++)
			efree(argv[i]);

		efree(argv);
	}
	else
	{
	    WRONG_PARAM_COUNT;
	}
	return;
}
/* }}} */



/* {{{ proto mixed rrd_graph(string file, array args_arr, int argc)
	Creates a graph based on options passed via an array */

PHP_FUNCTION(rrd_graph)
{
	pval *file, *args, *p_argc;
	pval *entry;
	zval *p_calcpr;
	HashTable *args_arr;
	int i, xsize, ysize, argc;
	char **argv, **calcpr;
    

	if ( rrd_test_error() )
		rrd_clear_error();
    
	if ( ZEND_NUM_ARGS() == 3 && 
		zend_get_parameters(ht, 3, &file, &args, &p_argc) == SUCCESS)
	{
		if ( args->type != IS_ARRAY )
		{ 
			php_error(E_WARNING, "2nd Variable passed to rrd_graph is not an array!\n");
			RETURN_FALSE;
		}
        
		convert_to_long(p_argc);
		convert_to_string(file);

		convert_to_array(args);
		args_arr = args->value.ht;

		argc = p_argc->value.lval + 3;
		argv = (char **) emalloc(argc * sizeof(char *));
 
		argv[0] = "dummy";
		argv[1] = estrdup("graph");
		argv[2] = estrdup(file->value.str.val);

		for (i = 3; i < argc; i++) 
		{
			pval **dataptr;

			if ( zend_hash_get_current_data(args_arr, (void *) &dataptr) == FAILURE )
				continue;

			entry = *dataptr;

			if ( entry->type != IS_STRING )
				convert_to_string(entry);

			argv[i] = estrdup(entry->value.str.val);

			if ( i < argc )
				zend_hash_move_forward(args_arr);
		}
   
		optind = 0; opterr = 0; 
		if ( rrd_graph(argc-1, &argv[1], &calcpr, &xsize, &ysize) != -1 )
		{
			array_init(return_value);
			add_assoc_long(return_value, "xsize", xsize);
			add_assoc_long(return_value, "ysize", ysize);

			MAKE_STD_ZVAL(p_calcpr);
			array_init(p_calcpr);
    
			if (calcpr)
			{
				for (i = 0; calcpr[i]; i++)
				{
					add_next_index_string(p_calcpr, calcpr[i], 1);
					free(calcpr[i]);
				}
				free(calcpr);
			}
			zend_hash_update(return_value->value.ht, "calcpr", sizeof("calcpr"), 
							(void *)&p_calcpr, sizeof(zval *), NULL);
		}
		else
		{
			RETVAL_FALSE;
		}
		for (i = 1; i < argc; i++)
			efree(argv[i]);

		efree(argv);
	}
	else
	{ 
		WRONG_PARAM_COUNT;
	}
	return;
}
/* }}} */



/* {{{ proto mixed rrd_fetch(string file, array args_arr, int p_argc)
	Fetch info from an RRD file */

PHP_FUNCTION(rrd_fetch)
{
	pval *file, *args, *p_argc;
	pval *entry;
	pval *p_start, *p_end, *p_step, *p_ds_cnt;
	HashTable *args_arr;
	zval *p_ds_namv, *p_data;
	int i, j, argc;
	time_t start, end;
	unsigned long step, ds_cnt;
	char **argv, **ds_namv; 
	rrd_value_t *data, *datap;
    
	if ( rrd_test_error() )
		rrd_clear_error();
    
	if ( ZEND_NUM_ARGS() == 3 && 
		 zend_get_parameters(ht, 3, &file, &args, &p_argc) == SUCCESS)
	{
		if ( args->type != IS_ARRAY )
		{ 
			php_error(E_WARNING, "2nd Variable passed to rrd_fetch is not an array!\n");
			RETURN_FALSE;
		}
        
		convert_to_long(p_argc);
		convert_to_string(file);

		convert_to_array(args);
		args_arr = args->value.ht;

		argc = p_argc->value.lval + 3;
		argv = (char **) emalloc(argc * sizeof(char *));
 
		argv[0] = "dummy";
		argv[1] = estrdup("fetch");
		argv[2] = estrdup(file->value.str.val);

		for (i = 3; i < argc; i++) 
		{
			pval **dataptr;

			if ( zend_hash_get_current_data(args_arr, (void *) &dataptr) == FAILURE )
				continue;

			entry = *dataptr;

			if ( entry->type != IS_STRING )
				convert_to_string(entry);

			argv[i] = estrdup(entry->value.str.val);

			if ( i < argc )
				zend_hash_move_forward(args_arr);
		}
  
		optind = 0; opterr = 0; 

		if ( rrd_fetch(argc-1, &argv[1], &start,&end,&step,&ds_cnt,&ds_namv,&data) != -1 )
		{
			array_init(return_value);
			add_assoc_long(return_value, "start", start);
			add_assoc_long(return_value, "end", end);
			add_assoc_long(return_value, "step", step);
			add_assoc_long(return_value, "ds_cnt", ds_cnt);

			MAKE_STD_ZVAL(p_ds_namv);
			MAKE_STD_ZVAL(p_data);
			array_init(p_ds_namv);
			array_init(p_data);
   
			if (ds_namv)
			{
				for (i = 0; i < ds_cnt; i++)
				{
					add_next_index_string(p_ds_namv, ds_namv[i], 1);
					free(ds_namv[i]);
				}
				free(ds_namv);
			}

			if (data)
			{
				datap = data;
 
				for (i = start; i <= end; i += step)
					for (j = 0; j < ds_cnt; j++)
						add_next_index_double(p_data, *(datap++));
 
				free(data);
			}

			zend_hash_update(return_value->value.ht, "ds_namv", sizeof("ds_namv"), 
							(void *)&p_ds_namv, sizeof(zval *), NULL);
			zend_hash_update(return_value->value.ht, "data", sizeof("data"), 
							(void *)&p_data, sizeof(zval *), NULL);
		}
		else
		{
			RETVAL_FALSE;
		}
		for (i = 1; i < argc; i++)
			efree(argv[i]);

		efree(argv);
	}
	else
	{ 
		WRONG_PARAM_COUNT;
	}
	return;
}
/* }}} */

#endif	/* HAVE_RRDTOOL */
