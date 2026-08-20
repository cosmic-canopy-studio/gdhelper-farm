/**
 * Flamenco Custom Job Type: CC5 Character Bake
 *
 * Bakes a CC5 FBX character into a game-ready GLB using Blender headless
 * with cc_blender_tools + GPU acceleration.
 *
 * Place this file in the scripts/ directory next to flamenco-manager.exe,
 * then restart the manager.
 */

const JOB_TYPE = {
    label: "CC5 Character Bake",
    description: "Import CC5 FBX, bake textures (Godot target), export GLB",
    settings: [
        {
            key: "input_file",
            type: "string",
            required: true,
            description: "Path to the CC5 FBX file (on shared storage)",
            visible: "submission",
        },
        {
            key: "output_file",
            type: "string",
            required: true,
            description: "Output GLB path (on shared storage)",
            visible: "submission",
        },
        {
            key: "resolution",
            type: "int32",
            default: 2048,
            description: "Bake texture resolution in pixels",
            visible: "submission",
        },
        {
            key: "use_gpu",
            type: "bool",
            default: true,
            description: "Use GPU (OptiX/CUDA) for baking",
            visible: "submission",
        },
        {
            key: "bake_script",
            type: "string",
            default: "{job_storage}/../../tools/farm/cc5_bake.py",
            description: "Path to the cc5_bake.py script",
            visible: "setting",
        },
    ],
};

function compileJob(job) {
    const settings = job.settings;
    const inputFile = settings.input_file;
    const outputFile = settings.output_file;
    const resolution = settings.resolution || 2048;
    const useGpu = settings.use_gpu !== false;
    const bakeScript = settings.bake_script;

    print(`CC5 Bake: ${inputFile} → ${outputFile} @ ${resolution}px`);

    // Single task: run Blender headless with the bake script
    const task = author.Task("bake", "blender");

    const args = [
        "--background",
        "--factory-startup",
        "--python", path.resolve(bakeScript),
        "--",
        "--input", inputFile,
        "--output", outputFile,
        "--resolution", String(resolution),
    ];

    if (!useGpu) {
        args.push("--no-gpu");
    }

    task.command("blender-render", {
        exe: "{blender}",
        exeArgs: JSON.stringify(args),
        argsBefore: [],
        blendfile: "",
        args: args,
    });

    // Alternative: use the exec command directly
    task.command("exec", {
        exe: "{blender}",
        args: [
            "--background",
            "--factory-startup",
            "--python", bakeScript,
            "--",
            "--input", inputFile,
            "--output", outputFile,
            "--resolution", String(resolution),
            ...(useGpu ? [] : ["--no-gpu"]),
        ],
    });

    job.addTask(task);
}
