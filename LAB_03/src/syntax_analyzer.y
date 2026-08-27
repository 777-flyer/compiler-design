%{

#include "symbol_table.h"

#define YYSTYPE symbol_info*

extern FILE *yyin;
int yyparse(void);
int yylex(void);
extern YYSTYPE yylval;

// our symbol table, one hash table per scope, 10 buckets per scope table
symbol_table *sym_table = new symbol_table(10);

// a function's parameters get built up here (by param_list) while its
// header is being parsed, then consumed by compound_statement as soon as
// the function's own scope is entered
vector<symbol_info*> temp_params;

// the names being declared in a variable_decl get built up here (by
// declaration_list) then consumed by variable_decl once the type is known
vector<symbol_info*> temp_decls;

// name/return-type of the function whose header is currently being
// parsed -- stashed by func_header, read back by param_list (to word
// "...in parameter of FUNCNAME") and by func_definition
string current_func_name;
string current_func_type;

// declaration_list/param_list only give us a display string like
// "int a,float b" -- these two helpers pull the info back out of it
// (the only commas in that string are the parameter/name separators)
int count_items(string s)
{
	if (s.length() == 0)
	{
		return 0;
	}
	int count = 1;
	for (int i = 0; i < s.length(); i++)
	{
		if (s[i] == ',')
		{
			count++;
		}
	}
	return count;
}

string comma_space(string s)
{
	string result = "";
	for (int i = 0; i < s.length(); i++)
	{
		if (s[i] == ',')
		{
			result += ", ";
		}
		else
		{
			result += s[i];
		}
	}
	return result;
}

bool is_zero_literal(string s)
{
	if (s.length() == 0)
	{
		return false;
	}
	for (int i = 0; i < s.length(); i++)
	{
		if (s[i] != '0' && s[i] != '.')
		{
			return false;
		}
	}
	return true;
}

vector<string> split_comma(string s)
{
	vector<string> result;
	if (s.length() == 0)
	{
		return result;
	}
	string cur = "";
	for (int i = 0; i < s.length(); i++)
	{
		if (s[i] == ',')
		{
			result.push_back(cur);
			cur = "";
		}
		else
		{
			cur += s[i];
		}
	}
	result.push_back(cur);
	return result;
}

string first_word(string s)
{
	int i = 0;
	while (i < s.length() && s[i] == ' ')
	{
		i++;
	}
	string result = "";
	while (i < s.length() && s[i] != ' ')
	{
		result += s[i];
		i++;
	}
	return result;
}

int lines = 1;
int error_count = 0;

ofstream outlog;
ofstream errorlog;

void report_error(string msg)
{
	outlog<<"At line no: "<<lines<<" "<<msg<<endl<<endl;
	errorlog<<"At line no: "<<lines<<" "<<msg<<endl<<endl;
	error_count++;
}

void yyerror(char *s)
{
	outlog<<"At line "<<lines<<" "<<s<<endl<<endl;

    // you may need to reinitialize variables if you find an error
}

%}

%token IF ELSE FOR WHILE DO BREAK INT CHAR FLOAT DOUBLE VOID RETURN SWITCH CASE DEFAULT CONTINUE PRINTLN ADDOP MULOP INCOP DECOP RELOP ASSIGNOP LOGICOP NOT LPAREN RPAREN LCURL RCURL LTHIRD RTHIRD COMMA SEMICOLON CONST_INT CONST_FLOAT ID

%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%%

start : program
	{
		outlog<<"At line no: "<<lines<<" start : program "<<endl<<endl;
		outlog<<"Symbol Table"<<endl<<endl;

		sym_table->print_all_scopes(outlog);
	}
	;

program : program unit
	{
		outlog<<"At line no: "<<lines<<" program : program unit "<<endl<<endl;
		outlog<<$1->get_name()+"\n"+$2->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name()+"\n"+$2->get_name(),"program");
	}
	| unit
	{
		outlog<<"At line no: "<<lines<<" program : unit "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name(),"program");
	}
	;

unit : variable_decl
	 {
		outlog<<"At line no: "<<lines<<" unit : variable_decl "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name(),"unit");
	 }
     | func_definition
     {
		outlog<<"At line no: "<<lines<<" unit : func_definition "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name(),"unit");
	 }
     ;

// factored out of func_definition's two alternatives on purpose: yacc
// can't tell apart two mid-rule actions that look identical sitting at
// the same position in two alternatives sharing a prefix (a genuine
// reduce/reduce conflict) -- funneling both alternatives through one
// shared "type_specifier ID" reduction avoids it
func_header : type_specifier ID
		{
			current_func_name = $2->get_name();
			current_func_type = $1->get_name();
			$$ = $1;
		}
		;

func_definition : func_header LPAREN param_list RPAREN
		{
			// the function's own name has to go into the ENCLOSING scope
			// before its body is parsed (not after) -- otherwise it
			// wouldn't be visible yet when the body's own scope gets
			// printed on exit, and a function couldn't call itself
			symbol_info *func_sym = new symbol_info(current_func_name, "ID");
			func_sym->set_symbol_category("Function Definition");
			func_sym->set_data_type(current_func_type);
			func_sym->set_param_count(count_items($3->get_name()));
			func_sym->set_param_details(comma_space($3->get_name()));
			if (!sym_table->insert(func_sym))
			{
				report_error("Multiple declaration of function "+current_func_name);
			}
		}
		compound_statement
		{
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN param_list RPAREN compound_statement "<<endl<<endl;
			outlog<<current_func_type<<" "<<current_func_name<<"("+$3->get_name()+")\n"<<$6->get_name()<<endl<<endl;

			$$ = new symbol_info(current_func_type+" "+current_func_name+"("+$3->get_name()+")\n"+$6->get_name(),"func_def");
		}
		| func_header LPAREN RPAREN
		{
			symbol_info *func_sym = new symbol_info(current_func_name, "ID");
			func_sym->set_symbol_category("Function Definition");
			func_sym->set_data_type(current_func_type);
			func_sym->set_param_count(0);
			func_sym->set_param_details("");
			if (!sym_table->insert(func_sym))
			{
				report_error("Multiple declaration of function "+current_func_name);
			}
		}
		compound_statement
		{
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN RPAREN compound_statement "<<endl<<endl;
			outlog<<current_func_type<<" "<<current_func_name<<"()\n"<<$5->get_name()<<endl<<endl;

			$$ = new symbol_info(current_func_type+" "+current_func_name+"()\n"+$5->get_name(),"func_def");
		}
 		;

param_list : param_list COMMA type_specifier ID
		{
			outlog<<"At line no: "<<lines<<" param_list : param_list COMMA type_specifier ID "<<endl<<endl;
			outlog<<$1->get_name()<<","<<$3->get_name()<<" "<<$4->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+","+$3->get_name()+" "+$4->get_name(),"param_list");

			bool duplicate = false;
			for (int i = 0; i < temp_params.size(); i++)
			{
				if (temp_params[i]->get_name() == $4->get_name())
				{
					duplicate = true;
				}
			}
			if (duplicate)
			{
				report_error("Multiple declaration of variable "+$4->get_name()+" in parameter of "+current_func_name);
			}

			symbol_info *p = new symbol_info($4->get_name(), "ID");
			p->set_symbol_category("Variable");
			p->set_data_type($3->get_name());
			temp_params.push_back(p);
		}
		| param_list COMMA type_specifier
		{
			outlog<<"At line no: "<<lines<<" param_list : param_list COMMA type_specifier "<<endl<<endl;
			outlog<<$1->get_name()<<","<<$3->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+","+$3->get_name(),"param_list");

			symbol_info *p = new symbol_info("", "ID");
			p->set_symbol_category("Variable");
			p->set_data_type($3->get_name());
			temp_params.push_back(p);
		}
 		| type_specifier ID
 		{
			outlog<<"At line no: "<<lines<<" param_list : type_specifier ID "<<endl<<endl;
			outlog<<$1->get_name()<<" "<<$2->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+" "+$2->get_name(),"param_list");

			temp_params.clear();
			symbol_info *p = new symbol_info($2->get_name(), "ID");
			p->set_symbol_category("Variable");
			p->set_data_type($1->get_name());
			temp_params.push_back(p);
		}
		| type_specifier
		{
			outlog<<"At line no: "<<lines<<" param_list : type_specifier "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"param_list");

			temp_params.clear();
			symbol_info *p = new symbol_info("", "ID");
			p->set_symbol_category("Variable");
			p->set_data_type($1->get_name());
			temp_params.push_back(p);
		}
 		;

compound_statement : LCURL
			{
				sym_table->enter_scope();
				for (int i = 0; i < temp_params.size(); i++)
				{
					if (temp_params[i]->get_name() != "")
					{
						sym_table->insert(temp_params[i]);
					}
				}
				temp_params.clear();
			}
			statements RCURL
			{
 		    	outlog<<"At line no: "<<lines<<" compound_statement : LCURL statements RCURL "<<endl<<endl;
				outlog<<"{\n"+$3->get_name()+"\n}"<<endl<<endl;

				$$ = new symbol_info("{\n"+$3->get_name()+"\n}","comp_stmnt");

				sym_table->print_all_scopes(outlog);
				sym_table->exit_scope();
 		    }
 		    | LCURL
 		    {
				sym_table->enter_scope();
				for (int i = 0; i < temp_params.size(); i++)
				{
					if (temp_params[i]->get_name() != "")
					{
						sym_table->insert(temp_params[i]);
					}
				}
				temp_params.clear();
			}
			RCURL
 		    {
 		    	outlog<<"At line no: "<<lines<<" compound_statement : LCURL RCURL "<<endl<<endl;
				outlog<<"{\n}"<<endl<<endl;

				$$ = new symbol_info("{\n}","comp_stmnt");

				sym_table->print_all_scopes(outlog);
				sym_table->exit_scope();
 		    }
 		    ;

variable_decl : type_specifier declaration_list SEMICOLON
		 {
			outlog<<"At line no: "<<lines<<" variable_decl : type_specifier declaration_list SEMICOLON "<<endl<<endl;
			outlog<<$1->get_name()<<" "<<$2->get_name()<<";"<<endl<<endl;

			$$ = new symbol_info($1->get_name()+" "+$2->get_name()+";","var_dec");

			for (int i = 0; i < temp_decls.size(); i++)
			{
				if ($1->get_name() == "void")
				{
					report_error("variable type can not be void ");
					temp_decls[i]->set_data_type("error");
					sym_table->insert(temp_decls[i]);
				}
				else
				{
					temp_decls[i]->set_data_type($1->get_name());
					if (!sym_table->insert(temp_decls[i]))
					{
						report_error("Multiple declaration of variable "+temp_decls[i]->get_name());
					}
				}
			}
			temp_decls.clear();
		 }
 		 ;

type_specifier : INT
		{
			outlog<<"At line no: "<<lines<<" type_specifier : INT "<<endl<<endl;
			outlog<<"int"<<endl<<endl;

			$$ = new symbol_info("int","type");
	    }
 		| FLOAT
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : FLOAT "<<endl<<endl;
			outlog<<"float"<<endl<<endl;

			$$ = new symbol_info("float","type");
	    }
 		| VOID
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : VOID "<<endl<<endl;
			outlog<<"void"<<endl<<endl;

			$$ = new symbol_info("void","type");
	    }
		| CHAR
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : CHAR "<<endl<<endl;
			outlog<<"char"<<endl<<endl;

			$$ = new symbol_info("char","type");
	    }
 		;

declaration_list : declaration_list COMMA ID
		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : declaration_list COMMA ID "<<endl<<endl;
 		  	outlog<<$1->get_name()+","<<$3->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+","+$3->get_name(),"decl_list");

			symbol_info *d = new symbol_info($3->get_name(), "ID");
			d->set_symbol_category("Variable");
			temp_decls.push_back(d);
 		  }
 		  | declaration_list COMMA ID LTHIRD CONST_INT RTHIRD //array after some declaration
 		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : declaration_list COMMA ID LTHIRD CONST_INT RTHIRD "<<endl<<endl;
 		  	outlog<<$1->get_name()+","<<$3->get_name()<<"["<<$5->get_name()<<"]"<<endl<<endl;

			$$ = new symbol_info($1->get_name()+","+$3->get_name()+"["+$5->get_name()+"]","decl_list");

			symbol_info *d = new symbol_info($3->get_name(), "ID");
			d->set_symbol_category("Array");
			d->set_array_size(stoi($5->get_name()));
			temp_decls.push_back(d);
 		  }
 		  |ID
 		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : ID "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"decl_list");

			temp_decls.clear();
			symbol_info *d = new symbol_info($1->get_name(), "ID");
			d->set_symbol_category("Variable");
			temp_decls.push_back(d);
 		  }
 		  | ID LTHIRD CONST_INT RTHIRD //array
 		  {
 		  	outlog<<"At line no: "<<lines<<" declaration_list : ID LTHIRD CONST_INT RTHIRD "<<endl<<endl;
			outlog<<$1->get_name()<<"["<<$3->get_name()<<"]"<<endl<<endl;

			$$ = new symbol_info($1->get_name()+"["+$3->get_name()+"]","decl_list");

			temp_decls.clear();
			symbol_info *d = new symbol_info($1->get_name(), "ID");
			d->set_symbol_category("Array");
			d->set_array_size(stoi($3->get_name()));
			temp_decls.push_back(d);
 		  }
 		  ;


statements : statement
	   {
	    	outlog<<"At line no: "<<lines<<" statements : statement "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"stmnts");
	   }
	   | statements statement
	   {
	    	outlog<<"At line no: "<<lines<<" statements : statements statement "<<endl<<endl;
			outlog<<$1->get_name()<<"\n"<<$2->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+"\n"+$2->get_name(),"stmnts");
	   }
	   ;

statement : variable_decl
	  {
	    	outlog<<"At line no: "<<lines<<" statement : variable_decl "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"stmnt");
	  }
	  | func_definition
	  {
	  		outlog<<"At line no: "<<lines<<" statement : func_definition "<<endl<<endl;
            outlog<<$1->get_name()<<endl<<endl;

            $$ = new symbol_info($1->get_name(),"stmnt");

	  }
	  | expression_statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : expression_statement "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"stmnt");
	  }
	  | compound_statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : compound_statement "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"stmnt");
	  }
	  | FOR LPAREN expression_statement expression_statement expression RPAREN statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : FOR LPAREN expression_statement expression_statement expression RPAREN statement "<<endl<<endl;
			outlog<<"for("<<$3->get_name()<<$4->get_name()<<$5->get_name()<<")\n"<<$7->get_name()<<endl<<endl;

			$$ = new symbol_info("for("+$3->get_name()+$4->get_name()+$5->get_name()+")\n"+$7->get_name(),"stmnt");
	  }
	  | IF LPAREN expression RPAREN statement %prec LOWER_THAN_ELSE
	  {
	    	outlog<<"At line no: "<<lines<<" statement : IF LPAREN expression RPAREN statement "<<endl<<endl;
			outlog<<"if("<<$3->get_name()<<")\n"<<$5->get_name()<<endl<<endl;

			$$ = new symbol_info("if("+$3->get_name()+")\n"+$5->get_name(),"stmnt");
	  }
	  | IF LPAREN expression RPAREN statement ELSE statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : IF LPAREN expression RPAREN statement ELSE statement "<<endl<<endl;
			outlog<<"if("<<$3->get_name()<<")\n"<<$5->get_name()<<"\nelse\n"<<$7->get_name()<<endl<<endl;

			$$ = new symbol_info("if("+$3->get_name()+")\n"+$5->get_name()+"\nelse\n"+$7->get_name(),"stmnt");
	  }
	  | WHILE LPAREN expression RPAREN statement
	  {
	    	outlog<<"At line no: "<<lines<<" statement : WHILE LPAREN expression RPAREN statement "<<endl<<endl;
			outlog<<"while("<<$3->get_name()<<")\n"<<$5->get_name()<<endl<<endl;

			$$ = new symbol_info("while("+$3->get_name()+")\n"+$5->get_name(),"stmnt");
	  }
	  | PRINTLN LPAREN ID RPAREN SEMICOLON
	  {
	    	outlog<<"At line no: "<<lines<<" statement : PRINTLN LPAREN ID RPAREN SEMICOLON "<<endl<<endl;
			outlog<<"printf("<<$3->get_name()<<");"<<endl<<endl;

			$$ = new symbol_info("printf("+$3->get_name()+");","stmnt");

			if (sym_table->lookup($3) == NULL)
			{
				report_error("Undeclared variable "+$3->get_name());
			}
	  }
	  | RETURN expression SEMICOLON
	  {
	    	outlog<<"At line no: "<<lines<<" statement : RETURN expression SEMICOLON "<<endl<<endl;
			outlog<<"return "<<$2->get_name()<<";"<<endl<<endl;

			$$ = new symbol_info("return "+$2->get_name()+";","stmnt");
	  }
	  ;

expression_statement : SEMICOLON
			{
				outlog<<"At line no: "<<lines<<" expression_statement : SEMICOLON "<<endl<<endl;
				outlog<<";"<<endl<<endl;

				$$ = new symbol_info(";","expr_stmt");
	        }
			| expression SEMICOLON
			{
				outlog<<"At line no: "<<lines<<" expression_statement : expression SEMICOLON "<<endl<<endl;
				outlog<<$1->get_name()<<";"<<endl<<endl;

				$$ = new symbol_info($1->get_name()+";","expr_stmt");
	        }
			;

variable : ID
      {
	    outlog<<"At line no: "<<lines<<" variable : ID "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		symbol_info *found = sym_table->lookup($1);
		if (found == NULL)
		{
			report_error("Undeclared variable "+$1->get_name());
			$$ = new symbol_info($1->get_name(),"varbl");
			$$->set_data_type("error");
		}
		else
		{
			if (found->get_symbol_category() == "Array")
			{
				report_error("variable is of array type : "+$1->get_name());
			}
			$$ = new symbol_info($1->get_name(),"varbl");
			$$->set_data_type(found->get_data_type());
			$$->set_symbol_category(found->get_symbol_category());
		}
	 }
	 | ID LTHIRD expression RTHIRD
	 {
	 	outlog<<"At line no: "<<lines<<" variable : ID LTHIRD expression RTHIRD "<<endl<<endl;
		outlog<<$1->get_name()<<"["<<$3->get_name()<<"]"<<endl<<endl;

		symbol_info *found = sym_table->lookup($1);
		if (found == NULL)
		{
			report_error("Undeclared variable "+$1->get_name());
			$$ = new symbol_info($1->get_name()+"["+$3->get_name()+"]","varbl");
			$$->set_data_type("error");
		}
		else
		{
			if (found->get_symbol_category() != "Array")
			{
				report_error("variable is not of array type : "+$1->get_name());
			}
			else if ($3->get_data_type() != "int" && $3->get_data_type() != "error")
			{
				report_error("array index is not of integer type : "+$1->get_name());
			}
			$$ = new symbol_info($1->get_name()+"["+$3->get_name()+"]","varbl");
			$$->set_data_type(found->get_data_type());
		}
	 }
	 ;

expression : logic_expression
	   {
	    	outlog<<"At line no: "<<lines<<" expression : logic_expression "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"expr");
			$$->set_data_type($1->get_data_type());
	   }
	   | variable ASSIGNOP logic_expression
	   {
	    	outlog<<"At line no: "<<lines<<" expression : variable ASSIGNOP logic_expression "<<endl<<endl;
			outlog<<$1->get_name()<<"="<<$3->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+"="+$3->get_name(),"expr");

			string ltype = $1->get_data_type();
			string rtype = $3->get_data_type();
			if (rtype == "void")
			{
				report_error("void function used in expression");
			}
			else if (ltype != "error" && rtype != "error")
			{
				if (ltype == "int" && rtype == "float")
				{
					report_error("warning: floating point value assigned to integer variable "+$1->get_name());
				}
				else if (ltype != rtype)
				{
					report_error("type mismatch in assignment of "+$1->get_name());
				}
			}
			$$->set_data_type(ltype);
	   }
	   ;

logic_expression : rel_expression
	     {
	    	outlog<<"At line no: "<<lines<<" logic_expression : rel_expression "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"lgc_expr");
			$$->set_data_type($1->get_data_type());
	     }
		 | rel_expression LOGICOP rel_expression
		 {
	    	outlog<<"At line no: "<<lines<<" logic_expression : rel_expression LOGICOP rel_expression "<<endl<<endl;
			outlog<<$1->get_name()<<$2->get_name()<<$3->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+$2->get_name()+$3->get_name(),"lgc_expr");

			if ($1->get_data_type() == "void" || $3->get_data_type() == "void")
			{
				report_error("void function used in expression");
			}
			$$->set_data_type("int");
	     }
		 ;

rel_expression	: simple_expression
		{
	    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"rel_expr");
			$$->set_data_type($1->get_data_type());
	    }
		| simple_expression RELOP simple_expression
		{
	    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression RELOP simple_expression "<<endl<<endl;
			outlog<<$1->get_name()<<$2->get_name()<<$3->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+$2->get_name()+$3->get_name(),"rel_expr");

			if ($1->get_data_type() == "void" || $3->get_data_type() == "void")
			{
				report_error("void function used in expression");
			}
			$$->set_data_type("int");
	    }
		;

simple_expression : term
          {
	    	outlog<<"At line no: "<<lines<<" simple_expression : term "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"simp_expr");
			$$->set_data_type($1->get_data_type());

	      }
		  | simple_expression ADDOP term
		  {
	    	outlog<<"At line no: "<<lines<<" simple_expression : simple_expression ADDOP term "<<endl<<endl;
			outlog<<$1->get_name()<<$2->get_name()<<$3->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+$2->get_name()+$3->get_name(),"simp_expr");

			string lt = $1->get_data_type();
			string rt = $3->get_data_type();
			if (lt == "void" || rt == "void")
			{
				report_error("void function used in expression");
				$$->set_data_type("error");
			}
			else if (lt == "error" || rt == "error")
			{
				$$->set_data_type("error");
			}
			else if (lt == "float" || rt == "float")
			{
				$$->set_data_type("float");
			}
			else
			{
				$$->set_data_type("int");
			}
	      }
		  ;

term :	unary_expression //term can be void because of un_expr->factor
     {
	    	outlog<<"At line no: "<<lines<<" term : unary_expression "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"term");
			$$->set_data_type($1->get_data_type());

	 }
     |  term MULOP unary_expression
     {
	    	outlog<<"At line no: "<<lines<<" term : term MULOP unary_expression "<<endl<<endl;
			outlog<<$1->get_name()<<$2->get_name()<<$3->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+$2->get_name()+$3->get_name(),"term");

			string op = $2->get_name();
			string lt = $1->get_data_type();
			string rt = $3->get_data_type();
			if (lt == "void" || rt == "void")
			{
				report_error("void function used in expression");
				$$->set_data_type("error");
			}
			else if (lt == "error" || rt == "error")
			{
				$$->set_data_type("error");
			}
			else if (op == "%")
			{
				if (lt != "int" || rt != "int")
				{
					report_error("operands of modulus must be integer");
					$$->set_data_type("error");
				}
				else if (is_zero_literal($3->get_name()))
				{
					report_error("second operand of % is zero");
					$$->set_data_type("error");
				}
				else
				{
					$$->set_data_type("int");
				}
			}
			else if (op == "/")
			{
				if (is_zero_literal($3->get_name()))
				{
					report_error("second operand of / is zero");
					$$->set_data_type("error");
				}
				else if (lt == "float" || rt == "float")
				{
					$$->set_data_type("float");
				}
				else
				{
					$$->set_data_type("int");
				}
			}
			else
			{
				if (lt == "float" || rt == "float")
				{
					$$->set_data_type("float");
				}
				else
				{
					$$->set_data_type("int");
				}
			}

	 }
     ;

unary_expression : ADDOP unary_expression  // un_expr can be void because of factor
		 {
	    	outlog<<"At line no: "<<lines<<" unary_expression : ADDOP unary_expression "<<endl<<endl;
			outlog<<$1->get_name()<<$2->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name()+$2->get_name(),"un_expr");
			if ($2->get_data_type() == "void")
			{
				report_error("void function used in expression");
				$$->set_data_type("error");
			}
			else
			{
				$$->set_data_type($2->get_data_type());
			}
	     }
		 | NOT unary_expression
		 {
	    	outlog<<"At line no: "<<lines<<" unary_expression : NOT unary_expression "<<endl<<endl;
			outlog<<"!"<<$2->get_name()<<endl<<endl;

			$$ = new symbol_info("!"+$2->get_name(),"un_expr");
			if ($2->get_data_type() == "void")
			{
				report_error("void function used in expression");
				$$->set_data_type("error");
			}
			else
			{
				$$->set_data_type("int");
			}
	     }
		 | factor_info
		 {
	    	outlog<<"At line no: "<<lines<<" unary_expression : factor_info "<<endl<<endl;
			outlog<<$1->get_name()<<endl<<endl;

			$$ = new symbol_info($1->get_name(),"un_expr");
			$$->set_data_type($1->get_data_type());
	     }
		 ;
factor_info : factor	{
	    outlog<<"At line no: "<<lines<<" factor_info : factor "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name(),"fctr_info");
		$$->set_data_type($1->get_data_type());
	}
	;
factor	: variable
    {
	    outlog<<"At line no: "<<lines<<" factor : variable "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name(),"fctr");
		$$->set_data_type($1->get_data_type());
	}
	| ID LPAREN argument_list RPAREN
	{
	    outlog<<"At line no: "<<lines<<" factor : ID LPAREN argument_list RPAREN "<<endl<<endl;
		outlog<<$1->get_name()<<"("<<$3->get_name()<<")"<<endl<<endl;

		$$ = new symbol_info($1->get_name()+"("+$3->get_name()+")","fctr");

		symbol_info *found = sym_table->lookup($1);
		if (found == NULL || found->get_symbol_category() != "Function Definition")
		{
			report_error("Undeclared function: "+$1->get_name());
			$$->set_data_type("error");
		}
		else
		{
			int arg_count = count_items($3->get_name());
			if (arg_count != found->get_param_count())
			{
				report_error("Inconsistencies in number of arguments in function call: "+$1->get_name());
			}
			else
			{
				vector<string> arg_types = split_comma($3->get_data_type());
				vector<string> param_entries = split_comma(found->get_param_details());
				for (int i = 0; i < arg_count; i++)
				{
					string at = arg_types[i];
					string pt = first_word(param_entries[i]);
					if (at != "error" && at != pt && !(pt == "float" && at == "int"))
					{
						report_error("argument "+to_string(i+1)+" type mismatch in function call: "+$1->get_name());
					}
				}
			}
			$$->set_data_type(found->get_data_type());
		}
	}
	| LPAREN expression RPAREN
	{
	   	outlog<<"At line no: "<<lines<<" factor : LPAREN expression RPAREN "<<endl<<endl;
		outlog<<"("<<$2->get_name()<<")"<<endl<<endl;

		$$ = new symbol_info("("+$2->get_name()+")","fctr");
		$$->set_data_type($2->get_data_type());
	}
	| CONST_INT
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_INT "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name(),"fctr");
		$$->set_data_type("int");
	}
	| CONST_FLOAT
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_FLOAT "<<endl<<endl;
		outlog<<$1->get_name()<<endl<<endl;

		$$ = new symbol_info($1->get_name(),"fctr");
		$$->set_data_type("float");
	}
	| variable INCOP
	{
	    outlog<<"At line no: "<<lines<<" factor : variable INCOP "<<endl<<endl;
		outlog<<$1->get_name()<<"++"<<endl<<endl;

		$$ = new symbol_info($1->get_name()+"++","fctr");
		$$->set_data_type($1->get_data_type());
	}
	| variable DECOP
	{
	    outlog<<"At line no: "<<lines<<" factor : variable DECOP "<<endl<<endl;
		outlog<<$1->get_name()<<"--"<<endl<<endl;

		$$ = new symbol_info($1->get_name()+"--","fctr");
		$$->set_data_type($1->get_data_type());
	}
	;

argument_list : arguments
			  {
					outlog<<"At line no: "<<lines<<" argument_list : arguments "<<endl<<endl;
					outlog<<$1->get_name()<<endl<<endl;

					$$ = new symbol_info($1->get_name(),"arg_list");
					$$->set_data_type($1->get_data_type());
			  }
			  |
			  {
					outlog<<"At line no: "<<lines<<" argument_list :  "<<endl<<endl;
					outlog<<""<<endl<<endl;

					$$ = new symbol_info("","arg_list");
					$$->set_data_type("");
			  }
			  ;

arguments : arguments COMMA logic_expression
		  {
				outlog<<"At line no: "<<lines<<" arguments : arguments COMMA logic_expression "<<endl<<endl;
				outlog<<$1->get_name()<<","<<$3->get_name()<<endl<<endl;

				$$ = new symbol_info($1->get_name()+","+$3->get_name(),"arg");
				$$->set_data_type($1->get_data_type()+","+$3->get_data_type());
		  }
	      | logic_expression
	      {
				outlog<<"At line no: "<<lines<<" arguments : logic_expression "<<endl<<endl;
				outlog<<$1->get_name()<<endl<<endl;

				$$ = new symbol_info($1->get_name(),"arg");
				$$->set_data_type($1->get_data_type());
		  }
	      ;


%%

int main(int argc, char *argv[])
{
	if(argc != 2)
	{
		cout<<"Please input file name"<<endl;
		return 0;
	}
	yyin = fopen(argv[1], "r");
	outlog.open("log.txt", ios::trunc);
	errorlog.open("error.txt", ios::trunc);

	if(yyin == NULL)
	{
		cout<<"Couldn't open file"<<endl;
		return 0;
	}
	// Enter the global or the first scope here
	sym_table->enter_scope();

	yyparse();

	outlog<<endl<<"Total lines: "<<lines<<endl<<"Total errors: "<<error_count<<endl;
	errorlog<<"Total errors: "<<error_count<<endl;

	outlog.close();
	errorlog.close();

	fclose(yyin);

	return 0;
}
