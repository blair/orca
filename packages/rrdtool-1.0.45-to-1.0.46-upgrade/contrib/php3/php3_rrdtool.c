/*
 *
 * php3_rrdtool.c
 *
 *	PHP interface to RRD Tool.
 *
 *
 *       Joey Miller, <joeym@inficad.com> 
 *          SkyLynx / Inficad Communications
 *          2/12/2000
 *
 *
 * See README, INSTALL, and USAGE files for more details.
 *
 */

#include "dl/phpdl.h"
#include "rrd_tool.h"
#include "php3_rrdtool.h"


/* {{{ proto string rrd_error(void)
   Get the error message set by the last rrd tool function call */

void php3_rrd_error(INTERNAL_FUNCTION_PARAMETERS)
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

void php3_rrd_clear_error(INTERNAL_FUNCTION_PARAMETERS)
{
    if ( rrd_test_error() )
        rrd_clear_error();

    return;
}
/* }}} */



/* {{{ proto int rrd_update(string file, string opt) 
   Update an RRD file with values specified */

void php3_rrd_update(INTERNAL_FUNCTION_PARAMETERS)
{
    pval *file, *opt;
    char **argv;

    if ( rrd_test_error() )
        rrd_clear_error();

    if ( ARG_COUNT(ht) == 2 && 
         getParameters(ht, 2, &file, &opt) == SUCCESS )
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

void php3_rrd_last(INTERNAL_FUNCTION_PARAMETERS)
{
    pval *file;
    unsigned long retval;

    char **argv = (char **) emalloc(3 * sizeof(char *));
    
    if ( rrd_test_error() )
        rrd_clear_error();
    
    if (getParameters(ht, 1, &file) == SUCCESS)
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

void php3_rrd_create(INTERNAL_FUNCTION_PARAMETERS)
{
    pval *file, *args_arr, *p_argc;
    pval *entry;
    char **argv;
    int argc, i;

    if ( rrd_test_error() )
        rrd_clear_error();

    if ( ARG_COUNT(ht) == 3 && getParameters(ht, 3, &file, &args_arr, &p_argc) == SUCCESS )
    {
        if ( args_arr->type != IS_ARRAY )
        { 
            php3_error(E_WARNING, "2nd Variable passed to rrd_create is not an array!\n");
            RETURN_FALSE;
        }

        convert_to_long(p_argc);
        convert_to_string(file);

        argc = p_argc->value.lval + 3;
        argv = (char **) emalloc(argc * sizeof(char *));

        argv[0] = "dummy";
        argv[1] = estrdup("create");
        argv[2] = estrdup(file->value.str.val);

        for (i = 3; i < argc; i++) 
        {
            if ( _php3_hash_get_current_data(args_arr->value.ht, (void **) &entry) == FAILURE )
                continue;

            if ( entry->type != IS_STRING )
                convert_to_string(entry);

            argv[i] = estrdup(entry->value.str.val);

            if ( i < argc )
                _php3_hash_move_forward(args_arr->value.ht);
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

void php3_rrd_graph(INTERNAL_FUNCTION_PARAMETERS)
{
    pval *file, *args_arr, *p_argc;
    pval *entry, p_calcpr;
    int i, xsize, ysize, argc;
    char **argv, **calcpr;
    
    if ( rrd_test_error() )
        rrd_clear_error();
    
    if ( ARG_COUNT(ht) == 3 && 
         getParameters(ht, 3, &file, &args_arr, &p_argc) == SUCCESS)
    {
        if ( args_arr->type != IS_ARRAY )
        { 
            php3_error(E_WARNING, "2nd Variable passed to rrd_graph is not an array!\n");
            RETURN_FALSE;
        }
        
        convert_to_long(p_argc);
        convert_to_string(file);

        argc = p_argc->value.lval + 3;
        argv = (char **) emalloc(argc * sizeof(char *));
 
        argv[0] = "dummy";
        argv[1] = estrdup("graph");
        argv[2] = estrdup(file->value.str.val);

        for (i = 3; i < argc; i++) 
        {
            if ( _php3_hash_get_current_data(args_arr->value.ht, (void **) &entry) == FAILURE 
                 || entry->type != IS_STRING )
            {  
                continue;
            }
            argv[i] = estrdup(entry->value.str.val);

            if ( i < argc )
                _php3_hash_move_forward(args_arr->value.ht);
        }
   
        optind = 0; opterr = 0; 
        if ( rrd_graph(argc-1, &argv[1], &calcpr, &xsize, &ysize) != -1 )
        {
            array_init(return_value);
            add_assoc_long(return_value, "xsize", xsize);
            add_assoc_long(return_value, "ysize", ysize);

            array_init(&p_calcpr);
    
            if (calcpr)
            {
                for (i = 0; calcpr[i]; i++)
                {
                    add_next_index_string(&p_calcpr, calcpr[i], 1);
                    free(calcpr[i]);
                }
                free(calcpr);
            }
            _php3_hash_update(return_value->value.ht, "calcpr", sizeof("calcpr"), 
                              &p_calcpr, sizeof(pval), NULL);
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

void php3_rrd_fetch(INTERNAL_FUNCTION_PARAMETERS)
{
    pval *file, *args_arr, *p_argc;
    pval *entry;
    pval *p_start, *p_end, *p_step, *p_ds_cnt, p_ds_namv, p_data;
    int i, argc;
    time_t start, end;
    unsigned long step, ds_cnt;
    char **argv, **ds_namv; 
    rrd_value_t *data, *datap;
    
    if ( rrd_test_error() )
        rrd_clear_error();
    
    if ( ARG_COUNT(ht) == 3 && 
         getParameters(ht, 3, &file, &args_arr, &p_argc) == SUCCESS)
    {
        if ( args_arr->type != IS_ARRAY )
        { 
            php3_error(E_WARNING, "2nd Variable passed to rrd_fetch is not an array!\n");
            RETURN_FALSE;
        }
        
        convert_to_long(p_argc);
        convert_to_string(file);

        argc = p_argc->value.lval + 3;
        argv = (char **) emalloc(argc * sizeof(char *));
 
        argv[0] = "dummy";
        argv[1] = estrdup("fetch");
        argv[2] = estrdup(file->value.str.val);

        for (i = 3; i < argc; i++) 
        {
            if ( _php3_hash_get_current_data(args_arr->value.ht, (void **) &entry) == FAILURE 
                 || entry->type != IS_STRING )
            {  
                continue;
            }
            argv[i] = estrdup(entry->value.str.val);

            if ( i < argc )
                _php3_hash_move_forward(args_arr->value.ht);
        }
  
        optind = 0; opterr = 0; 

        if ( rrd_fetch(argc-1, &argv[1], &start,&end,&step,&ds_cnt,&ds_namv,&data) != -1 )
        {
            array_init(return_value);
            add_assoc_long(return_value, "start", start);
            add_assoc_long(return_value, "end", end);
            add_assoc_long(return_value, "step", step);
            add_assoc_long(return_value, "ds_cnt", ds_cnt);

            array_init(&p_ds_namv);
            array_init(&p_data);
   
            if (ds_namv)
            {
                for (i = 0; i < ds_cnt; i++)
                {
                    add_next_index_string(&p_ds_namv, ds_namv[i], 1);
                    free(ds_namv[i]);
                }
                free(ds_namv);
            }

            if (data)
            {
                datap = data;
 
                for (i = start; i <= end; i += step)
                    add_next_index_double(&p_data, *(datap++));
 
                free(data);
            }

            _php3_hash_update(return_value->value.ht, "ds_namv", sizeof("ds_namv"), 
                              &p_ds_namv, sizeof(pval), NULL);
            _php3_hash_update(return_value->value.ht, "data", sizeof("data"), 
                              &p_data, sizeof(pval), NULL);
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


function_entry rrdtool_functions[] = {
        {"rrd_error", php3_rrd_error, NULL},
        {"rrd_clear_error", php3_rrd_clear_error, NULL},
	{"rrd_graph", php3_rrd_graph, NULL},
	{"rrd_last", php3_rrd_last, NULL},
	{"rrd_fetch", php3_rrd_fetch, NULL},
        {"rrd_update", php3_rrd_update, NULL},
        {"rrd_create", php3_rrd_create, NULL},
	{NULL, NULL, NULL}
};


php3_module_entry rrdtool_module_entry = {
	"RRDTool", rrdtool_functions, NULL, NULL, NULL, NULL, NULL, 0, 0, 0, NULL
};

php3_module_entry *get_module(void) { return &rrdtool_module_entry; }
