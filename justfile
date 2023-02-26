# requires graphviz
display-concrete-tree sourcefile:
    zig build run -- {{sourcefile}} | dot -Tsvg > scratch/concrete-tree.svg && firefox scratch/concrete-tree.svg
