#include "scope_table.h"

extern ofstream outlog;

class symbol_table
{
private:
    scope_table *current_scope;
    int bucket_count;
    int current_scope_id;

public:
    symbol_table(int bucket_count);
    ~symbol_table();
    void enter_scope();
    void exit_scope();
    bool insert(symbol_info* symbol);
    bool remove(symbol_info* symbol);
    symbol_info* lookup(symbol_info* symbol);
    void print_current_scope();
    void print_all_scopes(ofstream& outlog);

    // you can add more methods if you need
};

// complete the methods of symbol_table class

symbol_table::symbol_table(int bucket_count)
{
    this->bucket_count = bucket_count;
    current_scope_id = 0;
    current_scope = NULL;
}

symbol_table::~symbol_table()
{
    while (current_scope != NULL)
    {
        scope_table *temp = current_scope;
        current_scope = current_scope->get_parent_scope();
        delete temp;
    }
}

void symbol_table::enter_scope()
{
    current_scope_id++;
    scope_table *new_scope = new scope_table(bucket_count, current_scope_id, current_scope);
    current_scope = new_scope;

    outlog << "New ScopeTable with ID " << current_scope_id << " created" << endl << endl;
}

void symbol_table::exit_scope()
{
    outlog << "Scopetable with ID " << current_scope->get_unique_id() << " removed" << endl << endl;

    scope_table *temp = current_scope;
    current_scope = current_scope->get_parent_scope();
    delete temp;
}

bool symbol_table::insert(symbol_info* symbol)
{
    return current_scope->insert_in_scope(symbol);
}

bool symbol_table::remove(symbol_info* symbol)
{
    return current_scope->delete_from_scope(symbol);
}

symbol_info* symbol_table::lookup(symbol_info* symbol)
{
    scope_table *temp = current_scope;
    while (temp != NULL)
    {
        symbol_info *found = temp->lookup_in_scope(symbol);
        if (found != NULL)
        {
            return found;
        }
        temp = temp->get_parent_scope();
    }
    return NULL;
}

void symbol_table::print_current_scope()
{
    current_scope->print_scope_table(outlog);
}

void symbol_table::print_all_scopes(ofstream& outlog)
{
    outlog<<"################################"<<endl<<endl;
    scope_table *temp = current_scope;
    while (temp != NULL)
    {
        temp->print_scope_table(outlog);
        temp = temp->get_parent_scope();
    }
    outlog<<"################################"<<endl<<endl;
}
