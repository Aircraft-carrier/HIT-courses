#include "semantic.h"

extern pNode root;

extern int yylineno;
extern int yyparse();
extern void yyrestart(FILE *);
extern int debug;

// 函数用于打印文件内容并添加行号
void printFileContentWithLineNumber(FILE *fp) {
    char buffer[1024]; 
    int lineNumber = 1; 
    long currentPos = ftell(fp);

    fseek(fp, 0, SEEK_SET);
    // printf("\033[42m");
    printf("--------------------------- Code ---------------------------\n");
    while (fgets(buffer, sizeof(buffer), fp) != NULL) {
        printf("%4d: %s", lineNumber++, buffer);
    }
    // printf("\033[0m");
    printf("\n------------------------------------------------------------\n");
    fseek(fp, currentPos, SEEK_SET);
}


unsigned lexError = FALSE;
unsigned synError = FALSE;

int main(int argc, char **argv)
{
    if (argc <= 1)
        return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f)
    {
        perror(argv[1]);
        return 1;
    }
    yyrestart(f);
    if(debug == 1){
        printFileContentWithLineNumber(f);
    }
    table = initTable();
    yyparse();
    if(debug == 1){
        print_tree(root, "",0);
    }
    deleteTable(table);
    free_nodes(root);
    return 0;
}
