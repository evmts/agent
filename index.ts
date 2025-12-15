import * as p from '@clack/prompts';

async function main() {
  p.intro('Welcome to the CLI App');

  const answers = await p.group(
    {
      name: () =>
        p.text({
          message: 'What is your name?',
          placeholder: 'Anonymous',
          validate: (value) => {
            if (!value) return 'Please enter a name.';
          },
        }),
      language: () =>
        p.select({
          message: 'What is your favorite programming language?',
          options: [
            { value: 'typescript', label: 'TypeScript' },
            { value: 'javascript', label: 'JavaScript' },
            { value: 'python', label: 'Python' },
            { value: 'rust', label: 'Rust' },
            { value: 'go', label: 'Go' },
          ],
        }),
      features: () =>
        p.multiselect({
          message: 'What features do you like?',
          options: [
            { value: 'types', label: 'Static Types' },
            { value: 'fast', label: 'Fast Compilation' },
            { value: 'ecosystem', label: 'Great Ecosystem' },
            { value: 'community', label: 'Active Community' },
          ],
        }),
      confirm: () =>
        p.confirm({
          message: 'Ready to continue?',
          initialValue: true,
        }),
    },
    {
      onCancel: () => {
        p.cancel('Operation cancelled.');
        process.exit(0);
      },
    }
  );

  if (answers.confirm) {
    const s = p.spinner();
    s.start('Processing your preferences');
    await new Promise((resolve) => setTimeout(resolve, 1500));
    s.stop('Done!');
  }

  p.note(
    `Name: ${answers.name}\nLanguage: ${answers.language}\nFeatures: ${(answers.features as string[]).join(', ')}`,
    'Your Preferences'
  );

  p.outro('Thanks for using the CLI App!');
}

main().catch(console.error);
