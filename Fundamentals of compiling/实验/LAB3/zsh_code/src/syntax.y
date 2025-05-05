%code requires {
    #include "semantic.h"
    typedef struct node *pNode;
}

%{
#include <stdio.h>
#include "lex.yy.c"
#include <string.h>
extern int debug;
extern int synError;
extern pTable table;
#define YYERROR_VERBOSE 1

// 当前声明类型（用于传递类型信息）
pType currentDeclType = NULL;
pType returnType = NULL;
int structDefState = 0;
pNode root;
void yyerror(const char *msg);
boolean addSymbol(char* name, pType type, int lineno);
void checkSymbolExists(char* name, int lineno);
void binaryOperation(pNode node);
void monocularOp(pNode node);
%}
// types

%union{
    pNode node; 
}

// tokens

%token <node> INT
%token <node> FLOAT
%token <node> ID
%token <node> TYPE
%token <node> COMMA
%token <node> DOT
%token <node> SEMI
%token <node> RELOP
%token <node> ASSIGNOP
%token <node> PLUS MINUS STAR DIV
%token <node> AND OR NOT 
%token <node> LP RP LB RB LC RC
%token <node> IF
%token <node> ELSE
%token <node> WHILE
%token <node> STRUCT
%token <node> RETURN
%token <node> INT8_ERROR INT16_ERROR FLOAT_ERROR ID_ERROR
// non-terminals

%type <node> Program ExtDefList ExtDef ExtDecList   //  High-level Definitions
%type <node> Specifier StructSpecifier OptTag Tag   //  Specifiers
%type <node> VarDec FunDec VarList ParamDec         //  Declarators
%type <node> CompSt StmtList Stmt                   //  Statements
%type <node> DefList Def Dec DecList                //  Local Definitions
%type <node> Exp Args                               //  Expressions

// precedence and associativity

%right ASSIGNOP
%left OR
%left AND
%left RELOP
%left PLUS MINUS
%left STAR DIV
%right NOT
%left DOT
%left LB RB
%left LP RP
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%%
// High-level Definitions
Program:            ExtDefList { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Program", 1, $1); root = $$; }
    ;
ExtDefList:         ExtDef ExtDefList                       { $$ = newNode(@$.first_line, NOT_A_TOKEN, "ExtDefList", 2, $1, $2); }
    |               /* empty */                             { $$ = NULL; } 
    ; 
ExtDef:             Specifier ExtDecList SEMI {
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "ExtDef", 3, $1, $2, $3);
                        currentDeclType = NULL; 
                    }
    |               Specifier SEMI { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "ExtDef", 2, $1, $2); 
                        currentDeclType = NULL; 
                    }
    |               Specifier FunDec CompSt {
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "ExtDef", 3, $1, $2, $3);
                        currentDeclType = NULL;
                    }
    |		        Specifier error SEMI		            { synError = TRUE; }
    |               error SEMI                              { synError = TRUE; }
    |		        Specifier error    		    	        { synError = TRUE; }
    ; 

ExtDecList:         VarDec { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "ExtDecList", 1, $1);
                        pNode id = $1;
                        while(id->child) id = id->child;
                        addSymbol(id->u.char_name, $1->semantic.type, @1.first_line);
                    }
    |               VarDec COMMA ExtDecList                 { $$ = newNode(@$.first_line, NOT_A_TOKEN, "ExtDecList", 3, $1, $2, $3); }
    |          	    VarDec error COMMA ExtDecList	        { synError = TRUE; }
    ; 

Specifier:          TYPE {
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Specifier", 1, $1);
                        if (strcmp($1->u.char_name, "int") == 0) {
                            $$->semantic.type = newType(BASIC, INT_TYPE);
                        } else {
                            $$->semantic.type = newType(BASIC, FLOAT_TYPE);
                        }
                        currentDeclType = $$->semantic.type;
                    }
    |               StructSpecifier {
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Specifier", 1, $1); 
                        pType Specifier = copyType($1->semantic.type);
                        $$->semantic.type = Specifier;
                        currentDeclType =  Specifier;
                    }
    ;

StructSpecifier:    STRUCT OptTag LC {
                        // 进入作用域：在解析完LC后立即压栈
                        addStackDepth(table->stack);
                        structDefState = 1;
                    } DefList RC {
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "StructSpecifier", 5, $1, $2, $3, $5, $6);
                        char *structName = NULL;
                        int isAnonymous = 0;
                        /* 处理结构体名称 */
                        if ($2) {
                            structName = newString($2->child->u.char_name); // 使用安全的字符串拷贝
                        } else {
                            // 匿名结构体处理
                            table->unNamedStructNum++;
                            char tempName[20] = {0};
                            sprintf(tempName, "%d", table->unNamedStructNum);
                            structName = newString(tempName); // 正确分配内存
                            isAnonymous = 1;
                        }
                        pType structType = newType(STRUCTURE, NULL, NULL);
                        pFieldList p = $5->semantic.fieldList;
                        structType->u.structure.field = $5->semantic.fieldList;
                        structType->u.structure.structName = newString(structName);
                        if (!isAnonymous){
                            minusStackDepth(table->stack);
                            addSymbol(structName, structType, @1.first_line);
                            addStackDepth(table->stack);
                        }
                        $$->semantic.type = structType;
                        // 退出作用域：处理完所有元素后清理栈
                        clearCurDepthStackList(table); 
                        structDefState = 0;                       
                    }
    |               STRUCT Tag {
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "StructSpecifier", 2, $1, $2); 
                        pItem structItem = searchTableItem(table, $2->child->u.char_name);
                        if (structItem == NULL || !isStructDef(structItem))
                        {
                            char msg[100] = {0};
                            sprintf(msg, "Undefined structure \"%s\".", $2->child->u.char_name);
                            pError(UNDEF_STRUCT, @1.first_line, msg);
                        }else {
                            $$->semantic.type  = newType(
                                STRUCTURE, newString(structItem->field->name),
                                copyFieldList(structItem->field->type->u.structure.field)
                            );
                        }
                    }
    |		        STRUCT error LC DefList RC		        { synError = TRUE; }
    |		        STRUCT OptTag LC error RC		        { synError = TRUE; }
    |		        STRUCT OptTag LC error 		            { synError = TRUE; }
    |		        STRUCT error			                { synError = TRUE; }
    ; 
OptTag:             ID                                      { $$ = newNode(@$.first_line, NOT_A_TOKEN, "OptTag", 1, $1); }
    |               /* empty */                             { $$ = NULL; }
    ; 

Tag:                ID                                      { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Tag", 1, $1); }
    ; 

VarDec:             ID { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "VarDec", 1, $1);
                        $$->semantic.type = copyType(currentDeclType);
                    }
    |               VarDec LB INT RB                        { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "VarDec", 4, $1, $2, $3, $4);
                        $$->semantic.type = newType(ARRAY, copyType($1->semantic.type), $3->u.int_number);
                    }
    |               VarDec LB error RB                      { synError = TRUE; }
    |		        VarDec LB error			                { synError = TRUE; }
    ; 

FunDec:             ID LP {
                        returnType = currentDeclType;
                        addStackDepth(table->stack);
                    } VarList RP {
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "FunDec", 4, $1, $2, $4, $5);
                        int argc = 0;
                        pFieldList p = $4->semantic.fieldList;
                        while(p){
                            argc++;
                            p = p->tail;
                        }
                        pType funcType = newType(FUNCTION, 
                            argc, copyFieldList($4->semantic.fieldList), 
                            copyType(returnType));
                        $$->semantic.type = funcType;
                        minusStackDepth(table->stack);
                        addSymbol($1->u.char_name, funcType, @1.first_line);
                    }
    |               ID LP RP { 
                        returnType = currentDeclType;
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "FunDec", 3, $1, $2, $3);
                        pType funcType = newType(FUNCTION, 0, NULL, copyType(returnType));
                        $$->semantic.type = funcType;
                        addSymbol($1->u.char_name, funcType, @1.first_line);
                    }
    |               ID LP error RP                          { synError = TRUE; }
    ;

VarList:            ParamDec COMMA VarList { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "VarList", 3, $1, $2, $3);
                        pFieldList param = $1->semantic.fieldList;
                        param->tail = $3->semantic.fieldList;
                        $$->semantic.fieldList = param;
                    }
    |               ParamDec { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "VarList", 1, $1); 
                        $$->semantic.fieldList = $1->semantic.fieldList;
                    }
    ; 

ParamDec:           Specifier VarDec { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "ParamDec", 2, $1, $2); 
                        pNode id = $2;
                        while(id->child) id = id->child;
                        $$->semantic.fieldList = newFieldList(id->u.char_name, copyType($2->semantic.type));
                        addSymbol(id->u.char_name, $2->semantic.type, @1.first_line);
                    }
    ; 

CompSt:             LC {
                        addStackDepth(table->stack);
                    }
                    DefList StmtList RC {
                        // 创建节点时跳过动作块的位置($2)
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "CompSt", 4, $1, $3, $4, $5);
                        
                        // 退出作用域：处理完所有元素后清理栈
                        clearCurDepthStackList(table);
                    }

StmtList:           Stmt StmtList                           { $$ = newNode(@$.first_line, NOT_A_TOKEN, "StmtList", 2, $1, $2); }
    |               /* empty */                             { $$ = NULL; }
    ; 

Stmt:               Exp SEMI                                { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Stmt", 2, $1, $2); }
    |               CompSt                                  { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Stmt", 1, $1); }
    |               RETURN Exp SEMI { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Stmt", 3, $1, $2, $3); 
                        pType expType = $2->semantic.type;
                        if (!checkType(returnType, expType))
                            pError(TYPE_MISMATCH_RETURN, @1.first_line,
                                "Type mismatched for return.");
                    }    
    |               IF LP Exp RP Stmt %prec LOWER_THAN_ELSE { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Stmt", 5, $1, $2, $3, $4, $5); }
    |               IF LP Exp RP Stmt ELSE Stmt             { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Stmt", 7, $1, $2, $3, $4, $5, $6, $7); }
    |		        IF LP Exp RP error ELSE Stmt	        { synError = TRUE; }
    |               WHILE LP Exp RP Stmt                    { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Stmt", 5, $1, $2, $3, $4, $5); }
    |               IF LP error RP Stmt %prec LOWER_THAN_ELSE { synError = TRUE; }
    |		        IF LP error RP Stmt ELSE Stmt	        { synError = TRUE; }
    |		        error LP Exp RP Stmt 		            { synError = TRUE; }
    ; 
// Local Definitions Def 返回 pfieldList
// 对于 int x; float y, z; 这类则需要遍历的链表末尾在加入。
DefList:            Def DefList { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "DefList", 2, $1, $2);
                        if($2 == NULL){
                            $$->semantic.fieldList = $1->semantic.fieldList;
                        } else {
                            pFieldList p = $1->semantic.fieldList;
                            while(p->tail) p = p->tail;
                            p->tail = $2->semantic.fieldList;
                            $$->semantic.fieldList = $1->semantic.fieldList;
                        } 
                    }
    |               /* empty */                             { $$ = NULL; }
    ;     
// 从 Specifier 中获得 Type, 为 DecList 的各个 Field 的 Type 赋值
Def:                Specifier DecList SEMI { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Def", 3, $1, $2, $3); 
                        $$->semantic.fieldList = $2->semantic.fieldList;
                    }
    ; 
// 对于类似 int x,y;这类的 field构建采用头插法。因为每次只要并入一个结点。
DecList:            Dec { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "DecList", 1, $1); 
                        pFieldList decField = $1->semantic.fieldList;
                        if(decField != NULL){
                            $$->semantic.fieldList = $1->semantic.fieldList;
                        } else {
                            $$->semantic.fieldList = NULL;
                        }
                        
                    }
    |               Dec COMMA DecList { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "DecList", 3, $1, $2, $3); 
                        pFieldList t1 = $1->semantic.fieldList;
                        pFieldList t2 = $3->semantic.fieldList;
                        // if(t2 != NULL){
                        //     t1->tail = t2;  
                        // }  // t2 空或不空实际效果相同
                        t1->tail = t2;  
                        $$->semantic.fieldList = t1;

                    }
    |		        Dec error DecList			            { $$ = NULL; }
    ; 
// 需要定义出错，则返回 NULL 的内容
Dec:                VarDec { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Dec", 1, $1); 
                        pNode id = $1;
                        while(id->child) id = id->child;
                        if(addSymbol(id->u.char_name, $1->semantic.type, @1.first_line)){
                            $$->semantic.fieldList = newFieldList(id->u.char_name, copyType($1->semantic.type));
                        } else {
                            $$->semantic.fieldList = NULL;
                        }
                    }
    |               VarDec ASSIGNOP Exp { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Dec", 3, $1, $2, $3);
                        $$->semantic.fieldList = NULL;
                        pType varType = $1->semantic.type;
                        pType expType = $3->semantic.type;
                        int flag = 0;
                        if(structDefState == 1){
                            pError(REDEF_FEILD, @1.first_line,
                               "Illegal initialize variable in struct.");
                            flag = 1;
                        }
                        if (!checkType(varType, expType))
                        {
                            // 类型不相符
                            pError(TYPE_MISMATCH_ASSIGN, @1.first_line,
                                "Type mismatched for assignment.");
                            flag = 1;
                        }
                        if (varType && varType->kind == ARRAY)
                        {
                            // 报错，对非basic类型赋值
                            pError(TYPE_MISMATCH_ASSIGN, @1.first_line,
                                "Illegal initialize variable.");
                            flag = 1;
                        }
                        pNode id = $1;
                        while(id->child) id = id->child;
                        
                        if(addSymbol(id->u.char_name, $1->semantic.type, @1.first_line) && (flag == 0)){
                            $$->semantic.fieldList = newFieldList(id->u.char_name, copyType($1->semantic.type));
                        } else {
                            $$->semantic.fieldList = NULL;
                        }
                    }
    ; 

// Expressions
Exp:                Exp ASSIGNOP Exp { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); 
                        $$->semantic.type = NULL;
                        pType p1 = $1->semantic.type;
                        pType p2 = $3->semantic.type;
                        pNode tchild = $1->child;
                        if (!strcmp(tchild->name, "ID") ||            // ID
                            (tchild->brother != NULL && 
                            (!strcmp(tchild->brother->name, "LB") ||  // Exp[]
                            !strcmp(tchild->brother->name, "DOT")))   // Exp.ID
                        )    
                        {
                            if (!checkType(p1, p2))  // 有一个为 NULL 返回 True
                            {
                                // 报错，类型不匹配
                                pError(TYPE_MISMATCH_ASSIGN, @1.first_line,
                                    "Type mismatched for assignment.");
                            }
                            else {
                                $$->semantic.type = copyType(p1);  // 若 p1 为 NULL 则返回空
                            }
                        }
                        else
                        {
                            // 报错，左值
                            pError(LEFT_VAR_ASSIGN,  @1.first_line,
                                "The left-hand side of an assignment must be avariable.");
                        }   
                    }
    |               Exp AND Exp                             { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); binaryOperation($$);}
    |               Exp OR Exp                              { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); binaryOperation($$);}
    |               Exp RELOP Exp                           { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); binaryOperation($$);}
    |               Exp PLUS Exp                            { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); binaryOperation($$);}
    |               Exp MINUS Exp                           { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); binaryOperation($$);}
    |               Exp STAR Exp                            { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); binaryOperation($$);}
    |               Exp DIV Exp                             { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3); binaryOperation($$);}
    |               LP Exp RP { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3);
                        $$->semantic.type = copyType($2->semantic.type);
                    }
    |               MINUS Exp                               { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 2, $1, $2); monocularOp($$);}
    |               NOT Exp                                 { $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 2, $1, $2); monocularOp($$);}
    |               ID LP Args RP { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 4, $1, $2, $3, $4);
                        pItem funcInfo = searchTableItem(table, $1->u.char_name);
                        // function not find
                        if (funcInfo == NULL)
                        {
                            char msg[100] = {0};
                            sprintf(msg, "Undefined function \"%s\".", $1->u.char_name);
                            pError(UNDEF_FUNC, @1.first_line, msg);
                        }
                        else if (funcInfo->field->type->kind != FUNCTION)
                        {
                            char msg[100] = {0};
                            sprintf(msg, "\"%s\" is not a function.", $1->u.char_name);
                            pError(NOT_A_FUNC, @1.first_line, msg);
                        }
                        else 
                        {
                            // 待修改 Args
                            pFieldList arg = funcInfo->field->type->u.function.argv;
                            pFieldList p = $3->semantic.fieldList;
                            while(p){
                                if(arg == NULL){
                                    char msg[100] = {0};
                                    sprintf(msg, "too many arguments to function \"%s\", except %d args.",
                                    funcInfo->field->name, funcInfo->field->type->u.function.argc);
                                    pError(FUNC_AGRC_MISMATCH, @1.first_line, msg);
                                    break;
                                }
                                pType realType = p->type;
                                if (!checkType(realType, arg->type))
                                {
                                    char msg[100] = {0};
                                    sprintf(msg, "Function \"%s\" is not applicable for arguments.",
                                            funcInfo->field->name);
                                    pError(FUNC_AGRC_MISMATCH,  @1.first_line, msg);
                                    break;
                                }
                                p = p->tail;
                                arg = arg->tail;
                            }
                            // 函数的参数错误，但是仍然返回 func 的 type
                            $$->semantic.type = copyType(funcInfo->field->type->u.function.returnType);
                        }
                    }
    |               ID LP RP { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3);
                        pItem funcInfo = searchTableItem(table, $1->u.char_name);
                        // function not find
                        if (funcInfo == NULL)
                        {
                            char msg[100] = {0};
                            sprintf(msg, "Undefined function \"%s\".", $1->u.char_name);
                            pError(UNDEF_FUNC, @1.first_line, msg);
                        }
                        else if (funcInfo->field->type->kind != FUNCTION)
                        {
                            char msg[100] = {0};
                            sprintf(msg, "\"%s\" is not a function.", $1->u.char_name);
                            pError(NOT_A_FUNC, @1.first_line, msg);
                        }
                        else
                        // 待修改：Error type 9 at Line 8: Function "func(int)" is not applicable for arguments"(int, int)".
                        {
                            if (funcInfo->field->type->u.function.argc != 0)
                            {
                                char msg[100] = {0};
                                sprintf(msg,
                                        "too few arguments to function \"%s\", except %d args.",
                                        funcInfo->field->name,
                                        funcInfo->field->type->u.function.argc);
                                pError(FUNC_AGRC_MISMATCH, @1.first_line, msg);
                            }
                            $$->semantic.type = copyType(funcInfo->field->type->u.function.returnType);
                        }  
                    }
    |               Exp LB Exp RB { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 4, $1, $2, $3, $4); 
                        $$->semantic.type = NULL;
                        pType p1 = $1->semantic.type;
                        pType p2 = $3->semantic.type;
                        if (!p1)
                        {
                            // 第一个exp为null，上层报错，这里不用再管
                        }
                        else if (p1 && p1->kind != ARRAY)
                        {
                            // 报错，非数组使用[]运算符
                            char msg[100] = {0};
                            sprintf(msg, "\"%s\" is not an array.", $1->child->u.char_name);
                            pError(NOT_A_ARRAY, @1.first_line, msg);
                        }
                        else if (!p2 || p2->kind != BASIC ||
                                p2->u.basic != INT_TYPE)
                        {
                            // 报错，不用int索引[] 
                            char msg[100] = {0};
                            if(!strcmp($3->child->name,"FLOAT")){
                                sprintf(msg, "\"%f\" is not an integer.", $3->child->u.float_number);
                            }else if(!strcmp($3->child->name,"ID")){
                                sprintf(msg, "\"%s\" is not an integer.", $3->child->u.char_name);
                            }
                            pError(NOT_A_INT, @1.first_line, msg);
                        }
                        else
                        {
                            $$->semantic.type = copyType(p1->u.array.elem);
                        }
                    }
    | 		        Exp LB error RB			                { synError = TRUE; }
    |               Exp DOT ID { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 3, $1, $2, $3);
                        $$->semantic.type = NULL;
                        pType p1 = $1->semantic.type;
                        if (!p1 || p1->kind != STRUCTURE ||
                            !p1->u.structure.structName)
                        {
                            // 报错，对非结构体使用.运算符
                            pError(ILLEGAL_USE_DOT, @1.first_line, "Illegal use of \".\".");      
                        }
                        else
                        {
                            pNode ref_id = $3;
                            pFieldList structfield = p1->u.structure.field;
                            // 在结构体的 field List 中查找是否存在对应 ID
                            while (structfield != NULL)
                            {
                                if (!strcmp(structfield->name, ref_id->u.char_name))
                                {
                                    break;
                                }
                                structfield = structfield->tail;
                            }
                            if (structfield == NULL)
                            {
                                // 报错，没有可以匹配的域名
                                printf("Error type %d at Line %d: Non-existent field \"%s\".\n", 14, @1.first_line, ref_id->u.char_name);
                                ;
                            }
                            else
                            {
                                $$->semantic.type = copyType(structfield->type);
                            }
                        }     
                    }
    |               ID { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 1, $1);
                        char* name = $1->u.char_name;
                        pItem tp = searchTableItem(table, name);
                        // if (tp == NULL || isStructDef(tp))
                        if (tp == NULL)
                        {
                            char msg[100] = {0};
                            sprintf(msg, "Undefined variable \"%s\".", $1->u.char_name);
                            pError(UNDEF_VAR, @1.first_line, msg);
                        }
                        else
                        {
                            $$->semantic.type = copyType(tp->field->type);
                        }
                    }
    |               INT { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 1, $1); 
                        $$->semantic.type = newType(BASIC, INT_TYPE);
                    }
    |               FLOAT { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Exp", 1, $1); 
                        $$->semantic.type = newType(BASIC, FLOAT_TYPE);
                    }
    |		        Exp ASSIGNOP error    		            { synError = TRUE; }
    |		        Exp AND error                   	    { synError = TRUE; }
    |		        Exp OR error          	  	            { synError = TRUE; }
    |		        Exp RELOP error       	   	            { synError = TRUE; }
    |		        Exp PLUS error        		            { synError = TRUE; }
    |               Exp MINUS error       		            { synError = TRUE; }
    |	            Exp STAR error        		            { synError = TRUE; }
    |	            Exp DIV error         	   	            { synError = TRUE; }
    |	            ID LP error RP        		            { synError = TRUE; }
    ; 
 /* |		        INT8_ERROR				                { synError = TRUE; }
    |               INT16_ERROR                             { synError = TRUE; }
    |               FLOAT_ERROR                             { synError = TRUE; }
    |               ID_ERROR				                { synError = TRUE; }
  */ 
Args :              Exp COMMA Args { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Args", 3, $1, $2, $3); 
                        pFieldList p = newFieldList("",copyType($1->semantic.type));
                        p->tail = $3->semantic.fieldList;
                        $$->semantic.fieldList = p;
                    }
    |               Exp { 
                        $$ = newNode(@$.first_line, NOT_A_TOKEN, "Args", 1, $1);
                        $$->semantic.fieldList = newFieldList("",copyType($1->semantic.type));
                    }
    ; 

%%

boolean addSymbol(char* name, pType type, int lineno) {
    if (name == NULL || type == NULL) {
        // fprintf(stderr, "Internal error: Invalid arguments to addSymbol() at line %d\n", lineno);
        return false;
    }
    pFieldList field = newFieldList(name, copyType(type)); 
    if (field == NULL) {
        fprintf(stderr, "Memory error: Failed to create field at line %d\n", lineno);
        return false;
    }
    pItem item = newItem(table->stack->curStackDepth, field);
    if (item == NULL) {
        deleteFieldList(field); // 释放已分配的field
        fprintf(stderr, "Memory error: Failed to create item at line %d\n", lineno);
        return false;
    }
    /* 冲突检查 */
    if (checkTableItemConflict(table, item)) {
        char msg[256] = {0}; 
        ErrorType errorType = UNDEFINED_ERROR;
        if(structDefState == 0){
            switch (type->kind) {
                case FUNCTION:
                    errorType = REDEF_FUNC;
                    sprintf(msg, "Redefined function \"%s\".", item->field->name);
                    break;
                default:
                    errorType = REDEF_VAR;
                    sprintf(msg, "Redefined variable \"%s\"", name);
                    break;
            }
        }else {
            switch (type->kind) {
                case BASIC:
                    sprintf(msg, "Redefined field \"%s\".", item->field->name);
                    errorType = REDEF_FEILD;
                    break;
                case STRUCTURE:
                    errorType = DUPLICATED_NAME;
                    sprintf(msg, "Duplicated name \"%s\".", item->field->name);
                    break;
                default:
                    break;
            }
        }

        pError(errorType, lineno, msg);
        deleteItem(item); 
        if(debug == 1){
            printf("---------------------\n- symbol %s fail \n---------------------\n",name);
        }
        return false;
    } else {
        addTableItem(table, item);
        if(debug == 1){
            printf("---------------------\n- symbol %s in table\n---------------------\n",name);
            printTable(table);
        }
        return true;
    }
}

void checkSymbolExists(char* name, int lineno) {
    pItem item = searchTableItem(table, name);
    if (!item) {
        fprintf(stderr, "Error type 1 at Line %d: Undefined '%s'\n", lineno, name);
    }
}

// EXP -> EXP OP EXP
void binaryOperation(pNode node){
    pNode e1 = node->child;
    pNode e2 = node->child->brother->brother;
    pType p1 = e1->semantic.type;
    pType p2 = e2->semantic.type;
    // OP = AND, OR, RELOP, PLUS, MINUS, STAR, DIV
    if (p1 && p2 && (p1->kind == ARRAY || p2->kind == ARRAY))
    {
        // 报错，数组，结构体运算
        pError(TYPE_MISMATCH_OP, e1->linenumber,
                "Type mismatched for operands.");
    }
    else if (!checkType(p1, p2))
    {
        // 报错，类型不匹配
        pError(TYPE_MISMATCH_OP, e1->linenumber,
                "Type mismatched for operands.");
    }
    else
    {
        if (p1 && p2)
        {
            node->semantic.type = copyType(p1);
        }
    }
}

void monocularOp(pNode node){
    pNode e1 = node->child->brother;
    pType p1 = e1->semantic.type;
    node->semantic.type = NULL;
    if (!p1 || p1->kind != BASIC)
    {
        // 报错，数组，结构体运算
        printf("Error type %d at Line %d: %s.\n", 7, node->child->linenumber,
                "TYPE_MISMATCH_OP");
    }
    else
    {
        node->semantic.type = copyType(p1);
    }
}

void yyerror(char const* msg){
    fprintf(stderr, "Error type B at line %d: %s.\n", yylineno, msg);
}