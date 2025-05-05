#include "semantic.h"
#include <stdio.h>

int debug = 0;

NodeMap nodeMaps[] = {
    {"ASSIGNOP", "ASSIGNOP: ="},
    {"RELOP", "RELOP"},
    {"PLUS", "PLUS: +"},
    {"MINUS", "MINUS: -"},
    {"STAR", "STAR: *"},
    {"DIV", "DIV: /"},
    {"AND", "AND: &&"},
    {"OR", "OR: ││"},
    {"DOT", "DOT: ."},
    {"NOT", "NOT: !"},
    {"TYPE", "TYPE"},
    {"LP", "LP: ("},
    {"RP", "RP: )"},
    {"LB", "LB: ["},
    {"RB", "RB: ]"},
    {"LC", "LC: {"},
    {"RC", "RC: }"},
    {"COMMA", "COMMA: ,"},
    {"SEMI", "SEMI: ;"},
    {"STRUCT", "STRUCT: struct"},
    {"RETURN", "RETURN: return"},
    {"IF", "IF: if"},
    {"ELSE", "ELSE: else"},
    {"WHILE", "WHILE: while"},
};

char *newString(char *src)
{
    if (src == NULL)
        return NULL;
    int length = strlen(src) + 1;
    char *p = (char *)malloc(sizeof(char) * length);
    assert(p != NULL);
    strncpy(p, src, length);
    return p;
}

pNode newNode(int lineNo, NodeType type, char *name, int argc,
              ...)
{
    pNode curNode = NULL;

    curNode = (pNode)malloc(sizeof(Node));

    assert(curNode != NULL);
    curNode->name = newString(name);
    curNode->linenumber = lineNo;
    curNode->type = type;

    va_list vaList;
    va_start(vaList, argc);

    pNode tempNode = va_arg(vaList, pNode);

    curNode->child = tempNode;

    for (int i = 1; i < argc; i++)
    {
        tempNode->brother = va_arg(vaList, pNode);
        if (tempNode->brother != NULL)
        {
            tempNode = tempNode->brother;
        }
    }

    va_end(vaList);
    return curNode;
}

pNode newTokenNode(int lineNo, NodeType type, char *tokenName, char *tokenText)
{
    pNode tokenNode = (pNode)malloc(sizeof(Node));
    int nameLength = strlen(tokenName) + 1;

    assert(tokenNode != NULL);

    tokenNode->linenumber = lineNo;
    tokenNode->type = type;
    tokenNode->name = newString(tokenName);

    // 根据不同类型处理tokenText
    switch (type)
    {
    case TOKEN_ID:
        strncpy(tokenNode->u.char_name, tokenText, sizeof(tokenNode->u.char_name) - 1);
        tokenNode->u.char_name[sizeof(tokenNode->u.char_name) - 1] = '\0';
        break;

    case TOKEN_INT:
        // 整型
        tokenNode->u.int_number = atoi(tokenText);
        break;

    case TOKEN_FLOAT:
        // 浮点型
        tokenNode->u.float_number = atof(tokenText);
        break;

    case TOKEN_TYPE:
        strncpy(tokenNode->u.char_name, tokenText, sizeof(tokenNode->u.char_name) - 1);
        tokenNode->u.char_name[sizeof(tokenNode->u.char_name) - 1] = '\0';
        break;

    case TOKEN_OTHER:
        break;

    default:
        // 默认处理或报错
        fprintf(stderr, "Unknown node type: %d\n", type);
        break;
    }

    tokenNode->child = NULL;
    tokenNode->brother = NULL;

    return tokenNode;
}

void free_nodes(pNode now)
{
    if (now->child != NULL)
    {
        pNode child = now->child;
        while (true)
        {
            pNode next_brother = child->brother;
            free_nodes(child);
            if (next_brother == NULL)
                break;
            child = next_brother;
        }
    }
    if (now->name != NULL)
    {
        free(now->name);
        now->name = NULL;
    }
    free((pNode)now);
}

const char *getDisplayName(const char *internalName)
{
    for (int i = 0; i < sizeof(nodeMaps) / sizeof(NodeMap); ++i)
    {
        if (strcmp(internalName, nodeMaps[i].internalName) == 0)
        {
            return nodeMaps[i].displayName;
        }
    }
    printf(COLOR_RESET);
    return internalName;
}

// 打印节点信息
void print_node(pNode now, const char *prefix, int is_last)
{
    printf("%s", prefix);
    if (is_last)
        printf("└─ ");
    else
        printf("├─ ");
    printf(COLOR_GREEN);
    switch (now->type)
    {
    case TOKEN_ID:
        printf("ID: %s", now->u.char_name);
        break;
    case TOKEN_TYPE:
        printf("TYPE: %s", now->u.char_name);
        break;
    case TOKEN_INT:
        printf("INT: %u", now->u.int_number);
        break;
    case TOKEN_FLOAT:
        printf("FLOAT: %f", now->u.float_number);
        break;
    default:
        printf("%s", getDisplayName(now->name));
    }
    printf("(%d)\n", now->linenumber);
    printf(COLOR_RESET);
}

void print_tree(pNode now, const char *prefix, bool is_last)
{
    if (now == NULL)
        return;

    print_node(now, prefix, is_last);

    // 计算新前缀长度：原前缀 + "│  "或"   " + null终止符
    size_t prefix_len = (prefix != NULL) ? strlen(prefix) : 0;
    char *new_prefix = malloc(prefix_len + 4 + 5); // +1 for null terminator
    if (new_prefix == NULL)
    {
        return;
    }

    // 安全地构建新前缀
    if (prefix != NULL && prefix_len > 0)
    {
        strncpy(new_prefix, prefix, prefix_len);
        new_prefix[prefix_len] = '\0'; // 确保以null结尾
    }
    else
    {
        new_prefix[0] = '\0';
    }

    strcat(new_prefix, is_last ? "   " : "│  ");

    if (now->child != NULL)
    {
        pNode child = now->child;
        while (child != NULL)
        {
            pNode next_brother = child->brother;
            print_tree(child, new_prefix, next_brother == NULL);
            child = next_brother;
        }
    }
    free(new_prefix);
}

pTable table;

/*******************************Type类函数*******************************/

/*
new 一个新的type
*/
/**
 * 创建新的类型对象
 * @param kind （BASIC/ARRAY/STRUCTURE/FUNCTION）
 * @param ...  可变参数，根据kind不同需要不同参数：
 *             - BASIC: (BasicType)
 *             - ARRAY: (pType elem, int size)
 *             - STRUCTURE: (char* structName, pFieldList field)
 *             - FUNCTION: (int argc, pFieldList argv, pType returnType)
 * @return 新创建的类型对象指针（调用者需负责释放内存）
 * @note 如果参数不符合要求会触发CHECK_AND_HANDLE_ERROR终止程序
 */
pType newType(Kind kind, ...)
{
    pType p = (pType)malloc(sizeof(Type));
    p->kind = kind;
    va_list vaList;
    switch (kind)
    {
    case BASIC:
        va_start(vaList, 1);
        p->u.basic = va_arg(vaList, BasicType);
        break;
    case ARRAY:
        va_start(vaList, 2);
        p->u.array.elem = va_arg(vaList, pType);
        p->u.array.size = va_arg(vaList, int);
        break;
    case STRUCTURE:
        va_start(vaList, 2);
        p->u.structure.structName = va_arg(vaList, char *);
        p->u.structure.field = va_arg(vaList, pFieldList);
        break;
    case FUNCTION:
        va_start(vaList, 3);
        p->u.function.argc = va_arg(vaList, int);
        p->u.function.argv = va_arg(vaList, pFieldList);
        p->u.function.returnType = va_arg(vaList, pType);
        break;
    default:
        break;
    }
    va_end(vaList);
    return p;
}

/*
复制type
*/
pType copyType(pType src)
{
    if (src == NULL)
        return NULL;
    pType p = (pType)malloc(sizeof(Type));
    p->kind = src->kind;
    BasicType kind = src->kind;
    switch (kind)
    {
    case BASIC:
        p->u.basic = src->u.basic;
        break;
    case ARRAY:
        p->u.array.elem = copyType(src->u.array.elem);
        p->u.array.size = src->u.array.size;
        break;
    case STRUCTURE:
        p->u.structure.structName = newString(src->u.structure.structName);
        p->u.structure.field = copyFieldList(src->u.structure.field);
        break;
    case FUNCTION:
        p->u.function.argc = src->u.function.argc;
        p->u.function.argv = copyFieldList(src->u.function.argv);
        p->u.function.returnType = copyType(src->u.function.returnType);
        break;
    default:
        break;
    }
    return p;
}

/*
删除type
*/
void deleteType(pType type)
{
    Kind kind = type->kind;
    switch (kind)
    {
    case BASIC:
        break;
    case ARRAY:
        deleteType(type->u.array.elem);
        type->u.array.elem = NULL;
        break;
    case STRUCTURE:
        if (type->u.structure.structName)
            free(type->u.structure.structName);
        type->u.structure.structName = NULL;
        if (type->u.structure.field)
        {
            pFieldList cur = type->u.structure.field;
            pFieldList temp = cur;
            while (temp)
            {
                temp = cur->tail;
                deleteFieldList(cur);
                cur = temp;
            }
        }
        type->u.structure.field = NULL;
        break;
    case FUNCTION:
        // 不是递归方式释放内存，节省内存使用
        if (type->u.function.argc)
        {
            pFieldList temp = type->u.function.argv;
            pFieldList cur = temp;
            while (temp)
            {
                temp = cur->tail;
                deleteFieldList(cur);
                cur = temp;
            }
            type->u.function.argv = NULL;
        }
        deleteType(type->u.function.returnType);
        type->u.function.returnType = NULL;
        break;
    default:
        break;
    }
    free((pType)type);
}

/*
判断两个类型是否一致
*/
boolean checkType(pType type1, pType type2)
{
    if (type1 == NULL ││ type2 == NULL)
        return TRUE;
    if (type1->kind == FUNCTION ││ type2->kind == FUNCTION) // 函数不能重复定义
        return FALSE;
    if (type1->kind != type2->kind)
        return FALSE;
    else
    {
        switch (type1->kind)
        {
        case BASIC:
            return type1->u.basic == type2->u.basic;
        case ARRAY:
            return checkType(type1->u.array.elem, type2->u.array.elem); // 只验证数元素，不验证数组大小
        case STRUCTURE:
            return !strcmp(type1->u.structure.structName,
                           type2->u.structure.structName); // 名等价
        }
    }
}

void printType(pType type)
{
    if (type == NULL)
    {
        printf("type is NULL.\n");
    }
    else
    {
        switch (type->kind)
        {
        case BASIC:
            printf("type kind: BASIC\n");
            if (type->u.basic == 1)
            {
                printf("type basic: FLOAT\n");
            }
            else
            {
                printf("type basic: INT\n");
            }

            break;
        case ARRAY:
            printf("type kind: ARRAY\n");
            printf("array size: %d\n", type->u.array.size);
            printType(type->u.array.elem);
            break;
        case STRUCTURE:
            printf("type kind: STRUCTURE\n");
            if (!type->u.structure.structName)
                printf("struct name is NULL\n");
            else
            {
                printf("struct name is %s\n", type->u.structure.structName);
            }
            printFieldList(type->u.structure.field);
            break;
        case FUNCTION:
            printf("type kind: FUNCTION\n");
            printf("function argc is %d\n", type->u.function.argc);
            printf("function args:\n");
            printFieldList(type->u.function.argv);
            printf("function return type:\n");
            printType(type->u.function.returnType);
            break;
        }
    }
}

/*********************************域链表函数******************************/
pFieldList newFieldList(char *newName, pType newType)
{
    pFieldList p = (pFieldList)malloc(sizeof(FieldList));
    p->name = newString(newName);
    p->type = newType; // 在使用 newFieldList 的时候还会嵌套使用 newType
    p->tail = NULL;
    return p;
}

pFieldList copyFieldList(pFieldList src)
{
    pFieldList head = NULL, cur = NULL;
    pFieldList temp = src;

    while (temp)
    {
        if (!head)
        {
            head = newFieldList(temp->name, copyType(temp->type));
            cur = head;
            temp = temp->tail;
        }
        else
        {
            head = newFieldList(temp->name, copyType(temp->type));
            cur = cur->tail;
            temp = temp->tail;
        }
    }
    return head;
}

void deleteFieldList(pFieldList fieldList)
{
    if (fieldList->name)
    {
        free(fieldList->name);
        fieldList->name = NULL;
    }
    if (fieldList->type)
    {
        deleteType(fieldList->type);
        fieldList->type = NULL;
    }
    // if (fieldList->tail)
    // {
    //     deleteFieldList(fieldList->tail);
    //     fieldList->tail = NULL;
    // }
    free(fieldList);
}

void setFieldListName(pFieldList p, char *newName)
{
    if (p->name != NULL)
    {
        free(p->name);
    }
    // int length = strlen(newName) + 1;
    // p->name = (char*)malloc(sizeof(char) * length);
    // strncpy(p->name, newName, length);
    p->name = newString(newName);
}

void printFieldList(pFieldList fieldList)
{
    if (fieldList == NULL)
        printf("fieldList is NULL\n");
    else
    {
        printf("fieldList name is: %s\n", fieldList->name);
        printf("FieldList Type:\n");
        printType(fieldList->type);
        printFieldList(fieldList->tail);
    }
}

/**************************表项函数**********************************/
pItem newItem(int symbolDepth, pFieldList pfield)
{
    pItem p = (pItem)malloc(sizeof(TableItem));
    p->symbolDepth = symbolDepth;
    p->field = pfield;
    p->nextHash = NULL;
    p->nextSymbol = NULL;
    return p;
}

void deleteItem(pItem item)
{
    if (item->field != NULL)
        deleteFieldList(item->field);
    item->field = NULL;
    free(item);
}

/**************************Hash表函数********************************/
pHash newHash()
{
    pHash p = (pHash)malloc(sizeof(HashTable)); // 新的hash表
    p->hashArray = (pItem *)malloc(sizeof(pItem) * HASH_TABLE_SIZE);
    for (int i = 0; i < HASH_TABLE_SIZE; i++)
    {
        p->hashArray[i] = NULL;
    }
    return p;
}

void deleteHash(pHash hash)
{
    for (int i = 0; i < HASH_TABLE_SIZE; i++)
    {
        pItem temp = hash->hashArray[i];
        while (temp)
        {
            pItem tdelete = temp;
            temp = temp->nextHash;
            deleteItem(tdelete);
        }
        hash->hashArray[i] = NULL;
    }
    free(hash->hashArray);
    hash->hashArray = NULL;
    free(hash);
}

pItem getHashHead(pHash hash, int index)
{
    return hash->hashArray[index];
}

void setHashHead(pHash hash, int index, pItem newVal)
{
    hash->hashArray[index] = newVal;
}

/***************************栈函数***********************************/
pStack newStack()
{
    pStack p = (pStack)malloc(sizeof(Stack));
    p->stackArray = (pItem *)malloc(sizeof(pItem) * HASH_TABLE_SIZE);
    for (int i = 0; i < HASH_TABLE_SIZE; i++)
    {
        p->stackArray[i] = NULL;
    }
    p->curStackDepth = 0;
    return p;
}

void deleteStack(pStack stack)
{
    free(stack->stackArray);
    stack->stackArray = NULL;
    stack->curStackDepth = 0;
    free(stack);
}

void addStackDepth(pStack stack)
{
    stack->curStackDepth++;
    // printf("add depth now -> %d\n",stack->curStackDepth);
}

void minusStackDepth(pStack stack)
{
    stack->curStackDepth--;
    // printf("minus depth now -> %d\n",stack->curStackDepth);
}

pItem getCurDepthStackHead(pStack stack)
{
    return stack->stackArray[stack->curStackDepth];
    // return p == NULL ? NULL : p->stackArray[p->curStackDepth];
}

void setCurDepthStackHead(pStack stack, pItem newVal)
{
    stack->stackArray[stack->curStackDepth] = newVal;
}

/**************************表函数***********************************/
/*
符号表包含hash表，栈，unNamedStructNum
*/
pTable initTable()
{
    pTable table = (pTable)malloc(sizeof(Table));
    table->hash = newHash();
    table->stack = newStack();
    table->unNamedStructNum = 0;
    return table;
};

void deleteTable(pTable table)
{
    deleteHash(table->hash);
    table->hash = NULL;
    deleteStack(table->stack);
    table->stack = NULL;
    free(table);
};

pItem searchTableItem(pTable table, char *name)
{
    unsigned hashCode = getHashCode(name);
    pItem temp = getHashHead(table->hash, hashCode);
    if (temp == NULL)
        return NULL;
    // 采用头插法更新链表，找到第一个同名变量极为最近声明的变量
    while (temp) // hash表项链表查询
    {
        if (!strcmp(temp->field->name, name))
            return temp;
        temp = temp->nextHash;
    }
    return NULL;
}

// Return false -> no confliction, true -> has confliction
/**
 * Checks if a new table item conflicts with existing items in the symbol table.
 *
 * @param table Pointer to the symbol table
 * @param item Pointer to the new item to check
 * @return TRUE if conflict found, FALSE otherwise
 */
boolean checkTableItemConflict(pTable table, pItem item)
{
    pItem temp = searchTableItem(table, item->field->name);
    if (temp == NULL)
        return FALSE;

    while (temp)
    {
        if (!strcmp(temp->field->name, item->field->name))
        {
            // Structure names must be unique within the different scope
            // and cannot share names with other variables
            if (temp->field->type->kind == STRUCTURE ││ item->field->type->kind == STRUCTURE)
                return TRUE;

            // Conflict if existing item is in the same scope level (stack depth)
            if (temp->symbolDepth == table->stack->curStackDepth)
                return TRUE;
        }
        temp = temp->nextHash;
    }

    // No conflict found:
    // - No matching name found, or
    // - Matching name exists but is neither a structure nor in the same scope
    return FALSE;
}

/*
    Table before
    =============================================================
    │                      ┌─────────┬──────────┐               │
    │   Hash Table         │ Depth 0 │ Depth 1  │  Scope Chain  │
    │   ┌─────────┐        └─────────┴──────────┘               │
    │   │Bucket 0 │             │                               │
    │   ├─────────┤             │                               │
    │   │Bucket 1 │────> ItemA  │                               │
    │   ├─────────┤             │                               │
    │   │Bucket 2 │             │                               │
    │   ├─────────┤             ▼                               │
    │   │Bucket 3 │────────▶ ItemB ──▶  ItemC                  │
    │   └─────────┘                                             │
    =============================================================
*/

void addTableItem(pTable table, pItem item)
{
    unsigned hashCode = getHashCode(item->field->name);
    pHash hash = table->hash;
    pStack stack = table->stack;
    item->nextSymbol = getCurDepthStackHead(stack);
    setCurDepthStackHead(stack, item);

    item->nextHash = getHashHead(hash, hashCode);
    setHashHead(hash, hashCode, item);
}
/*
    Table after
    =============================================================
    │                      ┌─────────┬──────────┐               │
    │   Hash Table         │ Depth 0 │ Depth 1  │  Scope Chain  │
    │   ┌─────────┐        └─────────┴──────────┘               │
    │   │Bucket 0 │             │                               │
    │   ├─────────┤             ▼                               │
    │   │Bucket 1 │────────▶ NEW_Item ──▶  ItemA               │
    │   ├─────────┤             │                               │
    │   │Bucket 2 │             │                               │
    │   ├─────────┤             ▼                               │
    │   │Bucket 3 │────────▶ ItemB ──▶  ItemC                  │
    │   └─────────┘                                             │
    =============================================================
*/

// 在清除栈的时候使用
void deleteTableItem(pTable table, pItem item)
{
    unsigned hashCode = getHashCode(item->field->name);
    if (item == getHashHead(table->hash, hashCode))
        setHashHead(table->hash, hashCode, item->nextHash);
    else
    {
        pItem cur = getHashHead(table->hash, hashCode);
        pItem last = cur;
        while (cur != item)
        {
            last = cur;
            cur = cur->nextHash;
        }
        last->nextHash = cur->nextHash;
    }
    deleteItem(item);
}

boolean isStructDef(pItem src)
{
    if (src == NULL)
        return FALSE;
    if (src->field->type->kind != STRUCTURE)
        return FALSE;
    if (src->field->type->u.structure.structName == NULL)
        return FALSE;
    return TRUE;
}

void clearCurDepthStackList(pTable table)
{
    pStack stack = table->stack;
    pItem temp = getCurDepthStackHead(stack);
    while (temp)
    {
        pItem tDelete = temp;
        temp = temp->nextSymbol;
        deleteTableItem(table, tDelete);
    }
    setCurDepthStackHead(stack, NULL);
    minusStackDepth(stack);
}

// for Debug
void printTable(pTable table)
{
    printf("----------------hash_table----------------\n\n");
    for (int i = 0; i < HASH_TABLE_SIZE; i++)
    {
        pItem item = getHashHead(table->hash, i);
        if (item)
        {
            printf("[%d]", i);
            while (item)
            {
                printf(" ->\033[32m name: %s\033[0m \033[34mdepth: %d\033[0m\n", item->field->name,
                       item->symbolDepth);
                printf("========FiledList========\n");
                printFieldList(item->field);
                printf("===========End===========\n");
                item = item->nextHash;
            }
            printf("\n");
        }
    }
    printf("-------------------end--------------------\n");
}

void pError(ErrorType type, int line, char *msg)
{
    printf("Error type %d at Line %d: %s\n", type, line, msg);
}

unsigned int getHashCode(char *name)
{
    unsigned int val = 0, i;
    for (; *name; ++name)
    {
        val = (val << 2) + *name;
        if (i = val & ~HASH_TABLE_SIZE)
            val = (val ^ (i >> 12)) & HASH_TABLE_SIZE;
    }
    return val;
}