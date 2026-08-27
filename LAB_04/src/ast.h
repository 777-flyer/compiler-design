#ifndef AST_H
#define AST_H

#include <iostream>
#include <vector>
#include <string>
#include <fstream>
#include <map>

using namespace std;

class ASTNode {
public:
    virtual ~ASTNode() {}
    virtual string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp, int& temp_count, int& label_count) const = 0;
};

// Expression node types

class ExprNode : public ASTNode {
protected:
    string node_type; // Type information (int, float, void, etc.)
public:
    ExprNode(string type) : node_type(type) {}
    virtual string get_type() const { return node_type; }
};

// Variable node (for ID references)

class VarNode : public ExprNode {
private:
    string name;
    ExprNode* index; // For array access, nullptr for simple variables

public:
    VarNode(string name, string type, ExprNode* idx = nullptr)
        : ExprNode(type), name(name), index(idx) {}
    
    ~VarNode() { if(index) delete index; }
    
    bool has_index() const { return index != nullptr; }
    
    string generate_index_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                              int& temp_count, int& label_count) const {
        // the index is itself just an expression -- evaluate it like any other
        string idx_place = index->generate_code(outcode, symbol_to_temp, temp_count, label_count);

        // scale the index by this array's own element size, so a[i] lands
        // on the i-th element's actual byte offset, not the i-th byte --
        // get_type() here is the ARRAY's element type (int/float), set
        // from the symbol table when this VarNode was built, not a
        // per-access lookup
        int elem_size = (get_type() == "float" || get_type() == "double") ? 8 : 4;
        string scaled = "t" + to_string(temp_count++);
        outcode << scaled << " = " << idx_place << " * " << elem_size << endl;
        return scaled;
    }

    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        // compute the index (and its scaling) BEFORE allocating this node's
        // own result temp, so temp numbers stay in the same order the
        // instructions that use them actually appear in
        if (has_index()) {
            string idx_temp = generate_index_code(outcode, symbol_to_temp, temp_count, label_count);
            string temp = "t" + to_string(temp_count++);
            outcode << temp << " = " << name << "[" << idx_temp << "]" << endl;
            return temp;
        }
        string temp = "t" + to_string(temp_count++);
        outcode << temp << " = " << name << endl;
        return temp;
    }

    string get_name() const { return name; }
};

// Constant node

class ConstNode : public ExprNode {
private:
    string value;

public:
    ConstNode(string val, string type) : ExprNode(type), value(val) {}
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        string temp = "t" + to_string(temp_count++);
        outcode << temp << " = " << value << endl;
        return temp;
    }
};

// Binary operation node

class BinaryOpNode : public ExprNode {
private:
    string op;
    ExprNode* left;
    ExprNode* right;

public:
    BinaryOpNode(string op, ExprNode* left, ExprNode* right, string result_type)
        : ExprNode(result_type), op(op), left(left), right(right) {}
    
    ~BinaryOpNode() {
        delete left;
        delete right;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        string l = left->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        string r = right->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        string temp = "t" + to_string(temp_count++);
        outcode << temp << " = " << l << " " << op << " " << r << endl;
        return temp;
    }
};

// Unary operation node

class UnaryOpNode : public ExprNode {
private:
    string op;
    ExprNode* expr;

public:
    UnaryOpNode(string op, ExprNode* expr, string result_type)
        : ExprNode(result_type), op(op), expr(expr) {}
    
    ~UnaryOpNode() { delete expr; }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        string e = expr->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        string temp = "t" + to_string(temp_count++);
        outcode << temp << " = " << op << e << endl;
        return temp;
    }
};

// Assignment node

class AssignNode : public ExprNode {
private:
    VarNode* lhs;
    ExprNode* rhs;

public:
    AssignNode(VarNode* lhs, ExprNode* rhs, string result_type)
        : ExprNode(result_type), lhs(lhs), rhs(rhs) {}
    
    ~AssignNode() {
        delete lhs;
        delete rhs;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        string rhs_place = rhs->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        if (lhs->has_index()) {
            string idx_temp = lhs->generate_index_code(outcode, symbol_to_temp, temp_count, label_count);
            outcode << lhs->get_name() << "[" << idx_temp << "] = " << rhs_place << endl;
        } else {
            outcode << lhs->get_name() << " = " << rhs_place << endl;
        }
        return rhs_place;
    }
};

// Statement node types

class StmtNode : public ASTNode {
public:
    virtual string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                                int& temp_count, int& label_count) const = 0;
};

// Expression statement node

class ExprStmtNode : public StmtNode {
private:
    ExprNode* expr;

public:
    ExprStmtNode(ExprNode* e) : expr(e) {}
    ~ExprStmtNode() { if(expr) delete expr; }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        // return the inner expression's own place, not just "" -- the given
        // grammar reuses this same node to wrap a for-loop's init/condition/
        // update (cast to ExprNode*), and those need the real place back
        if (expr) {
            return expr->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        }
        return "";
    }
};

// Block (compound statement) node

class BlockNode : public StmtNode {
private:
    vector<StmtNode*> statements;

public:
    ~BlockNode() {
        for (auto stmt : statements) {
            delete stmt;
        }
    }
    
    void add_statement(StmtNode* stmt) {
        if (stmt) statements.push_back(stmt);
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        for (auto stmt : statements) {
            stmt->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        }
        return "";
    }
};

// If statement node

class IfNode : public StmtNode {
private:
    ExprNode* condition;
    StmtNode* then_block;
    StmtNode* else_block; // nullptr if no else part

public:
    IfNode(ExprNode* cond, StmtNode* then_stmt, StmtNode* else_stmt = nullptr)
        : condition(cond), then_block(then_stmt), else_block(else_stmt) {}
    
    ~IfNode() {
        delete condition;
        delete then_block;
        if (else_block) delete else_block;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        string cond = condition->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        int then_label = label_count++;
        int else_label = label_count++;
        int end_label = label_count++;

        outcode << "if " << cond << " goto L" << then_label << endl;
        outcode << "goto L" << else_label << endl;

        outcode << "L" << then_label << ":" << endl;
        then_block->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        outcode << "goto L" << end_label << endl;

        outcode << "L" << else_label << ":" << endl;
        if (else_block) {
            else_block->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        }

        outcode << "L" << end_label << ":" << endl;
        return "";
    }
};

// While statement node

class WhileNode : public StmtNode {
private:
    ExprNode* condition;
    StmtNode* body;

public:
    WhileNode(ExprNode* cond, StmtNode* body_stmt)
        : condition(cond), body(body_stmt) {}
    
    ~WhileNode() {
        delete condition;
        delete body;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        int cond_label = label_count++;
        int body_label = label_count++;
        int end_label = label_count++;

        outcode << "L" << cond_label << ":" << endl;
        string cond = condition->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        outcode << "if " << cond << " goto L" << body_label << endl;
        outcode << "goto L" << end_label << endl;

        outcode << "L" << body_label << ":" << endl;
        body->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        outcode << "goto L" << cond_label << endl;

        outcode << "L" << end_label << ":" << endl;
        return "";
    }
};

// For statement node

class ForNode : public StmtNode {
private:
    ExprNode* init;
    ExprNode* condition;
    ExprNode* update;
    StmtNode* body;

public:
    ForNode(ExprNode* init_expr, ExprNode* cond_expr, ExprNode* update_expr, StmtNode* body_stmt)
        : init(init_expr), condition(cond_expr), update(update_expr), body(body_stmt) {}
    
    ~ForNode() {
        if (init) delete init;
        if (condition) delete condition;
        if (update) delete update;
        delete body;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (init) {
            init->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        }

        int cond_label = label_count++;
        int body_label = label_count++;
        int end_label = label_count++;

        outcode << "L" << cond_label << ":" << endl;
        if (condition) {
            string cond = condition->generate_code(outcode, symbol_to_temp, temp_count, label_count);
            outcode << "if " << cond << " goto L" << body_label << endl;
            outcode << "goto L" << end_label << endl;
        }

        outcode << "L" << body_label << ":" << endl;
        body->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        if (update) {
            update->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        }
        outcode << "goto L" << cond_label << endl;

        outcode << "L" << end_label << ":" << endl;
        return "";
    }
};

// Return statement node

class ReturnNode : public StmtNode {
private:
    ExprNode* expr;

public:
    ReturnNode(ExprNode* e) : expr(e) {}
    ~ReturnNode() { if (expr) delete expr; }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        if (expr) {
            string val = expr->generate_code(outcode, symbol_to_temp, temp_count, label_count);
            outcode << "return " << val << endl;
        } else {
            outcode << "return" << endl;
        }
        return "";
    }
};

// Declaration node

class DeclNode : public StmtNode {
private:
    string type;
    vector<pair<string, int>> vars; // Variable name and array size (0 for regular vars)

public:
    DeclNode(string t) : type(t) {}
    
    void add_var(string name, int array_size = 0) {
        vars.push_back(make_pair(name, array_size));
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        // declarations don't need a real instruction, just a comment --
        // a variable only actually enters the code once something reads or
        // assigns it (VarNode/AssignNode handle that)
        for (const auto& v : vars) {
            if (v.second > 0) {
                outcode << "// Declaration: " << type << " " << v.first << "[" << v.second << "]" << endl;
            } else {
                outcode << "// Declaration: " << type << " " << v.first << endl;
            }
        }
        return "";
    }

    string get_type() const { return type; }
    const vector<pair<string, int>>& get_vars() const { return vars; }
};

// Function declaration node

class FuncDeclNode : public ASTNode {
private:
    string return_type;
    string name;
    vector<pair<string, string>> params; // Parameter type and name
    BlockNode* body;

public:
    FuncDeclNode(string ret_type, string n) : return_type(ret_type), name(n), body(nullptr) {}
    ~FuncDeclNode() { if (body) delete body; }
    
    void add_param(string type, string name) {
        params.push_back(make_pair(type, name));
    }
    
    void set_body(BlockNode* b) {
        body = b;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        string paramstr = "";
        for (size_t i = 0; i < params.size(); i++) {
            if (i > 0) paramstr += ", ";
            paramstr += params[i].first + " " + params[i].second;
        }
        outcode << "// Function: " << return_type << " " << name << "(" << paramstr << ")" << endl;

        if (body) {
            body->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        }
        outcode << endl;
        return "";
    }
};

// Helper class for function arguments

class ArgumentsNode : public ASTNode {
private:
    vector<ExprNode*> args;

public:
    ~ArgumentsNode() {
        // Don't delete args here - they'll be transferred to FuncCallNode
    }
    
    void add_argument(ExprNode* arg) {
        if (arg) args.push_back(arg);
    }
    
    ExprNode* get_argument(int index) const {
        if (index >= 0 && index < args.size()) {
            return args[index];
        }
        return nullptr;
    }
    
    size_t size() const {
        return args.size();
    }
    
    const vector<ExprNode*>& get_arguments() const {
        return args;
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        // This node doesn't generate code directly
        return "";
    }
};

// Function call node

class FuncCallNode : public ExprNode {
private:
    string func_name;
    vector<ExprNode*> arguments;

public:
    FuncCallNode(string name, string result_type)
        : ExprNode(result_type), func_name(name) {}
    
    ~FuncCallNode() {
        for (auto arg : arguments) {
            delete arg;
        }
    }
    
    void add_argument(ExprNode* arg) {
        if (arg) arguments.push_back(arg);
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        // each argument is evaluated and immediately "param"-ed, one at a
        // time, rather than evaluating all of them first
        for (auto arg : arguments) {
            string place = arg->generate_code(outcode, symbol_to_temp, temp_count, label_count);
            outcode << "param " << place << endl;
        }
        string temp = "t" + to_string(temp_count++);
        outcode << temp << " = call " << func_name << ", " << arguments.size() << endl;
        return temp;
    }
};

// Program node (root of AST)

class ProgramNode : public ASTNode {
private:
    vector<ASTNode*> units;

public:
    ~ProgramNode() {
        for (auto unit : units) {
            delete unit;
        }
    }
    
    void add_unit(ASTNode* unit) {
        if (unit) units.push_back(unit);
    }
    
    string generate_code(ofstream& outcode, map<string, string>& symbol_to_temp,
                        int& temp_count, int& label_count) const override {
        for (auto unit : units) {
            unit->generate_code(outcode, symbol_to_temp, temp_count, label_count);
        }
        return "";
    }
};

#endif // AST_H