#include<bits/stdc++.h>
using namespace std;

class symbol_info
{
private:
    string name;
    string type;

    // what kind of symbol it is: "Variable", "Array" or "Function Definition"
    string symbol_category;

    // the data type / return type of the symbol (int/float/void/char)
    string data_type;

    // array size, only meaningful when symbol_category is "Array"
    int array_size;

    // only meaningful when symbol_category is "Function Definition"
    int param_count;
    string param_details;

public:
    symbol_info(string name, string type)
    {
        this->name = name;
        this->type = type;
        array_size = 0;
        param_count = 0;
    }
    string get_name()
    {
        return name;
    }
    string get_type()
    {
        return type;
    }
    void set_name(string name)
    {
        this->name = name;
    }
    void set_type(string type)
    {
        this->type = type;
    }

    string get_symbol_category()
    {
        return symbol_category;
    }
    void set_symbol_category(string symbol_category)
    {
        this->symbol_category = symbol_category;
    }
    string get_data_type()
    {
        return data_type;
    }
    void set_data_type(string data_type)
    {
        this->data_type = data_type;
    }
    int get_array_size()
    {
        return array_size;
    }
    void set_array_size(int array_size)
    {
        this->array_size = array_size;
    }
    int get_param_count()
    {
        return param_count;
    }
    void set_param_count(int param_count)
    {
        this->param_count = param_count;
    }
    string get_param_details()
    {
        return param_details;
    }
    void set_param_details(string param_details)
    {
        this->param_details = param_details;
    }

    ~symbol_info()
    {
        // nothing to deallocate, symbol_info only holds strings/ints
    }
};
