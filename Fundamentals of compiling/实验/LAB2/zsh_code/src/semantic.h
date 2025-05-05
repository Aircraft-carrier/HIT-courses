#ifndef SEMANTIC_H
#define SEMANTIC_H

// #define HASH_TABLE_SIZE 0x3fff
#define HASH_TABLE_SIZE 15
#define STACK_DEEP
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "syntax.tab.h"
// #include <unistd.h>
#include <stdbool.h>
#include "enum.h"


// #define NAME_LENGTH 32
// #define VAL_LENGTH 64
#define COLOR_GREEN "\x1B[32m"
#define COLOR_RESET "\x1B[0m"


#define TRUE 1
#define FALSE 0
extern int debug;
/*

                                 name <- id
+-------------------+       +-------------------+       +-------------------+
│      Type         │       │    FieldList      │       │    TableItem      │
│-------------------│       │-------------------│       │-------------------│
│ Kind kind         │       │ char* name        │       │ int symbolDepth   │
│ union u    FUCTION│------>│ pType type        │------>│ pFieldList field  │
│ BASIC,ARRAY,STRUCT│<------│ pFieldList tail   │       │ pItem nextSymbol  │
+-------------------+       +-------------------+       │ pItem nextHash    │
                                                        +-------------------+
                                                                  │
          +-----------------------+-------------------------------+
          │                       │
+-------------------+   +-------------------+       +----------------------+
│    HashTable      │   │      Stack        │       │      Table           │
│-------------------│   │-------------------│       │----------------------│
│ pItem* hashArray  │---│ pItem* stackArray │------>│ pHash hash           │
+-------------------+   │ int curStackDepth │------>│ pStack stack         │
                        +-------------------+       │ int unNamedStructNum │
                                                    +----------------------+
*/


// 假设 Kind 和 BasicType 在其他地方已经定义  
typedef struct type *pType;  
typedef struct fieldList *pFieldList;  
typedef struct tableItem *pItem;  

// Type 结构体定义  
typedef struct type {  
    Kind kind; // 用于标识类型的种类  
    union {  
        BasicType basic; // 基本类型  
        struct {  
            pType elem;  // 数组元素类型  
            int size;    // 数组大小  
        } array;  
        struct {  
            char *structName; // 结构体名称  
            pFieldList field; // 字段列表  
        } structure;  
        struct {  
            int argc;         // 函数参数个数  
            pFieldList argv;  // 参数列表  
            pType returnType; // 返回类型  
        } function;  
    } u;  
} Type;  

// FieldList 结构体定义  
typedef struct fieldList {  
    char *name;           // 字段名称  
    pType type;          // 字段类型  
    pFieldList tail;     // 指向下一个字段  
} FieldList;  

// TableItem 结构体定义  
typedef struct tableItem {  
    int symbolDepth;     // 符号的作用域深度  
    pFieldList field;    // 字段列表  
    pItem nextSymbol;    // 同一深度下的下一个符号（链表）  
    pItem nextHash;      // 同一哈希码下的下一符号（链表）  
} TableItem;  

// NodeMap 映射表定义  
typedef struct {  
    const char *internalName; // 内部名称  
    const char *displayName;   // 显示名称  
} NodeMap;  

extern NodeMap nodeMaps[]; // 外部声明 nodeMaps  

// Node 结构体定义  
typedef struct node *pNode; // 定义指向 node 的指针类型  

#include "syntax.tab.h"

typedef struct node {  
    pNode child;              // 指向子节点  
    pNode brother;            // 指向同级兄弟节点  
    int linenumber;           // 行号  
    char *name;               // 节点名称  
    NodeType type;            // 节点类型标志  
    union {  
        char char_name[30];   // 字符串类型  
        int int_number;       // 整数类型  
        float float_number;   // 浮点数类型  
    } u;  

    // 语义信息部分  
    union {  
        pType type;           // 指向类型的指针  
        pFieldList fieldList; // 指向字段列表的指针  
    } semantic;  

} Node;  

// 布尔类型定义  
typedef unsigned boolean; // 用于布尔标志（可考虑使用 stdbool.h 代替）  

typedef unsigned boolean;

typedef struct hashTable *pHash;
typedef struct hashTable
{
    pItem *hashArray;
} HashTable;

typedef struct stack *pStack;
typedef struct stack
{
    pItem *stackArray;
    int curStackDepth;
} Stack;

typedef struct table *pTable;
typedef struct table
{
    pHash hash;
    pStack stack;
    int unNamedStructNum; // unNamedStructNum是来标记不同代码块
    // int enterStructLayer;
} Table;

extern pTable table;

char *newString(char *src);
pNode newNode(int lineNo, NodeType type, char *name, int argc, ...);
pNode newTokenNode(int lineNo, NodeType type, char *tokenName, char *tokenText);
void free_nodes(pNode now);
const char *getDisplayName(const char *internalName);
void print_node(pNode now, const char *prefix, int is_last);
void print_tree(pNode now, const char *prefix, bool is_last);

// Type functions
pType newType(Kind kind, ...);
pType copyType(pType src);
void deleteType(pType type);
boolean checkType(pType type1, pType type2);
void printType(pType type);

// FieldList functions
pFieldList newFieldList(char *newName, pType newType);
pFieldList copyFieldList(pFieldList src);
void deleteFieldList(pFieldList fieldList);
void setFieldListName(pFieldList p, char *newName);
void printFieldList(pFieldList fieldList);

// tableItem functions
pItem newItem(int symbolDepth, pFieldList pfield);
void deleteItem(pItem item);
boolean isStructDef(pItem src);

// Hash functions
pHash newHash();
void deleteHash(pHash hash);
pItem getHashHead(pHash hash, int index);
void setHashHead(pHash hash, int index, pItem newVal);

// Stack functions
pStack newStack();
void deleteStack(pStack stack);
void addStackDepth(pStack stack);
void minusStackDepth(pStack stack);
pItem getCurDepthStackHead(pStack stack);
void setCurDepthStackHead(pStack stack, pItem newVal);

// Table functions
pTable initTable();
void deleteTable(pTable table);
pItem searchTableItem(pTable table, char *name);
boolean checkTableItemConflict(pTable table, pItem item);
void addTableItem(pTable table, pItem item);
void deleteTableItem(pTable table, pItem item);
void clearCurDepthStackList(pTable table);
void printTable(pTable table);

// Global functions
// 告诉编译器在调用该函数时尽量将函数体的代码直接插入到调用点。
// 这可以减少函数调用的开销（如压栈、跳转等），提高代码执行效率，尤其是在小型函数或者频繁调用的函数中。
unsigned int getHashCode(char *name);

void pError(ErrorType type, int line, char *msg); 

#endif